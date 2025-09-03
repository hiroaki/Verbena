class MailQueue < ApplicationRecord
  # レコードを専有取得（ claim ）しようとした場合に、
  # 指定した session_id のレコードが既に存在する場合に投げる例外
  ClaimByNotNewSessionError = Class.new(StandardError)

  belongs_to :eml_source
  has_many :delivery_responses, dependent: :destroy

  validates :timer_at, presence: true
  validates :envelope_to, presence: true

  after_initialize :set_timer_at_if_blank

  delegate :eml, to: :eml_source

  # "セッション" の ID を発行します。
  # 要件：
  # - 毎回異なるユニークな値を返すこと
  # - 予約済みの文字列ではないこと
  #     現時点では予約済みとなるパターンはありませんが、将来のために、
  #     uuid が返すパターン以外の文字列は使わないでください。
  def self.issue_session_id
    SecureRandom.uuid
  end

  # 一度も処理されていないレコードの中で、現在時刻がタイマー時刻を経過しているレコードを、
  # session_id のセッション用に専有取得（claim）します。
  # 指定した session_id のレコードが存在する場合は例外を投げます。
  def self.claim_by_timer!(session_id)
    claim!(session_id, timer_at: ..Time.current)
  end

  # 一度も処理されていないレコードの中で、 id のレコードを、
  # session_id のセッション用に専有取得（claim）します。
  # 指定した session_id のレコードが存在する場合は例外を投げます。
  def self.claim_by_id!(session_id, id)
    claim!(session_id, id: id)
  end

  # 指定の condition の条件を満たすレコードを、 session_id のセッション用に専有取得（claim）します。
  # 並行実行時の安全性を確保するため、小さなバッチ単位で処理し、デッドロック時には指数バックオフで再試行します。
  # 影響を受けた行数の累計を返します。
  def self.claim!(session_id, condition)
    unless session_id.present?
      raise ArgumentError, 'The 1st argument "session_id" is not given'
    end

    if 0 < where(session_id: session_id).count
      raise ClaimByNotNewSessionError
    end

    claim_in_batches(session_id, condition)
  end
  private_class_method :claim!

  # バッチ単位での安全な claim 処理
  # 目的:
  # - 複数プロセス／ワーカーが同時に claim を実行しても重複して取得しないようにする
  # - デッドロック時には指数バックオフで再試行する
  #
  # 改修前の問題点（LIMIT + update_all パターン）:
  # - `where(...).limit(n).update_all(...)` のような書き方は DB アダプタ依存であり、
  #   MySQL では `UPDATE ... LIMIT n` が動作するが PostgreSQL 等ではサポートされない。
  #   そのためクロスデータベースでの互換性が失われる。
  # - また、ORM レベルで LIMIT を含む update_all を組み合わせると、期待通りに行数が制限されない
  #   ・silent な挙動差（期待した件数が更新されない or 全件更新される）を招く可能性がある。
  # - 更に LIMIT を伴う更新は DB によって最適なロック戦略が異なり、デッドロックの温床になることがある。
  #
  # 改修後の方針（ID を先に取得してから ID セットで update_all）:
  # 1. 小バッチ分のレコード ID を先に SELECT (pluck(:id)) する
  # 2. 取得した ID に対して WHERE id IN (...) で update_all を実行する
  #
  # 長所:
  # - PostgreSQL を含む主要 DB アダプタで動作する（portable）
  # - SQL 上で明示的に id の集合で更新するため、どのアダプタでも挙動が安定する
  # - update_all の戻り値で実際に更新された行数が分かるため、処理の健全性チェックが可能
  #
  # 注意点（残る制約）:
  # - pluck と update_all の間に TOCTOU (time-of-check-to-time-of-use) の窓があり、
  #   他プロセスが同じ id を同時に pluck して更新を試みる可能性は残る。
  #   ただし WHERE id IN (...) による更新は "現在その id を持つ行のみ" を更新するため、
  #   二重更新は発生しにくく、戻り値（更新件数）により実際に claim できた数を正確に把握できます。
  # - 完全に競合を排除するには SELECT ... FOR UPDATE 等を使う手もあるが、
  #   本実装はパフォーマンスと移植性のバランスを優先した実用的な選択です。
  def self.claim_in_batches(session_id, condition)
    batch_size = claim_batch_size
    max_retries = claim_max_retries
    total_claimed = 0
    current_time = Time.current

    retries = 0

    loop do
      ids = where(condition.merge(session_id: nil)).order(:id).limit(batch_size).pluck(:id)
      break if ids.empty?

      begin
        # Update by id set — portable and atomic across adapters
        claimed_count = where(id: ids).update_all(
          session_id: session_id,
          claimed_at: current_time,
          updated_at: current_time
        )

        total_claimed += claimed_count

        # If we fetched fewer than batch_size ids, we've exhausted available rows
        break if ids.length < batch_size

        # reset retry counter after a successful batch
        retries = 0
      rescue ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout => e
        if retries < max_retries - 1
          backoff_seconds = calculate_backoff_seconds(retries)
          Rails.logger.warn("[#{name}] Deadlock detected during claim, retrying in #{backoff_seconds}s (attempt #{retries + 1}/#{max_retries})")
          sleep(backoff_seconds)
          retries += 1
          next
        else
          # Max retries を超えた場合の対応（オペレーション上の推奨手順）:
          # - まず該当 session_id で更新されているレコードの一覧（id のサンプル、件数）をログに残す
          # - 自動で即座にクリアするのではなく、人の判断で回復処理を実行することを想定する
          # - 回復処理は以下のポリシーで実装するのが安全
          #     * 対象を "未配送（delivery_responses が無い）かつ 十分に古い claimed_at" に限定する
          #     * 実行前に dry-run が可能（どのレコードを消すかを確認できる）
          #     * 実行ログ（誰が実行したか、何件、どの session_id）を残す
          # - 具体的な回復アクション例:
          #     MailQueue.left_outer_joins(:delivery_responses)
          #              .where(session_id: session_id)
          #              .where(delivery_responses: { id: nil })
          #              .where('claimed_at < ?', 5.minutes.ago)
          #              .update_all(session_id: nil, claimed_at: nil, updated_at: Time.current)
          #
          # 将来的に自動化するには rake タスクを用意します（手動トリガー前提）:
          # - タスク名例: `verbena:claim:recover[SESSION_ID,only_undelivered,older_than,dry_run]`
          # - オプション: --dry-run, only_undelivered=true/false, older_than=5.minutes
          # - タスクはまず dry-run を表示し、確認後に実行できるフローにする
          # - テスト: ユニットテスト（recover メソッド）と rake タスクの統合テストを用意する
          #
          # ここではログ出力のみ行い、例外を再送出して上位（呼び出し元）に処理を委ねます。
          Rails.logger.error("[#{name}] Max retries exceeded for claim operation for session_id=[#{session_id}]: #{e.message}")
          raise
        end
      end
    end

    total_claimed
  end
  private_class_method :claim_in_batches

  # デッドロック検知やロックタイムアウトの際のリトライまでの待ち時間秒
  # TODO: Verbena::Settings の項目にし、そこから得るようにします。
  def self.calculate_backoff_seconds(retry_count)
    # 教科書的で安全な指数バックオフ + full jitter 実装
    # - base: 初期待ち時間（秒）
    # - cap: 最大待ち時間（秒）
    # full jitter: 0..max_delay を一様ランダムに取る
    base = 1.0
    cap  = 300.0

    # retry_count が大きくなるごとに指数的に増加するが cap を超えない
    max_delay = [base * (2 ** retry_count), cap].min

    # full jitter: 0 から max_delay までのランダム値を返す
    random_fraction * max_delay
  end
  private_class_method :calculate_backoff_seconds

  # Random fraction generator wrapped for easier testing (can be stubbed)
  def self.random_fraction
    rand
  end
  private_class_method :random_fraction

  # デッドロック検知やロックタイムアウトの際のリトライ最大数
  # TODO: Verbena::Settings の項目にし、そこから得るようにします。
  def self.claim_max_retries
    5
  end
  private_class_method :claim_max_retries

  # claim 処理のバッチサイズを取得
  def self.claim_batch_size
    # 環境設定から取得、デフォルトは20（競合を避けるため小さめ）
    Verbena::Settings.in_batches_config[:of] || 20
  end
  private_class_method :claim_batch_size

  # session_id のセッション用に専有取得（claim）されたレコードを返します。
  def self.claimed(session_id)
    where(session_id: session_id)
  end

  # 古い claim を解放します（デフォルト: 1時間以上前の claim）
  def self.release_stale_claims!(older_than: 1.hour.ago)
    stale_count = where.not(claimed_at: nil).where(claimed_at: ..older_than)
                  .update_all(session_id: nil, claimed_at: nil, updated_at: Time.current)
    
    if stale_count > 0
      Rails.logger.info("[#{name}] Released #{stale_count} stale claims older than #{older_than}")
    end
    
    stale_count
  end

  # claim されているが配送結果が存在しないレコードを返します（スタック検出用）
  def self.claimed_but_undelivered
    left_outer_joins(:delivery_responses)
      .where.not(session_id: nil)
      .where(delivery_responses: { id: nil })
  end

  # 結果がないレコードを返します。
  # このメソッドは単に、関連する DeliveryResponse にレコードが存在しない MailQueue(s) を返します。
  def self.undelivered
    where.missing(:delivery_responses)
  end

  private
    def set_timer_at_if_blank
      # 部分 SELECT で生成される部分属性オブジェクトでは timer_at カラム自体が無い場合があります。
      return unless has_attribute?(:timer_at)

      if timer_at.blank?
        self.timer_at = Time.current
      end
    end

  public
end
