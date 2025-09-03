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
  def self.claim_in_batches(session_id, condition)
    batch_size = claim_batch_size
    max_retries = 5  # 1秒間隔で5回リトライ（最大5秒）
    total_claimed = 0
    current_time = Time.current
    
    max_retries.times do |retry_count|
      begin
        # MySQL データベースでの原子的な更新操作を実行
        # session_id が NULL (未クレーム) の条件下で小バッチサイズの LIMIT 付き UPDATE を実行し、
        # 複数プロセスによる同時アクセス時の競合状態を回避する
        claimed_count = where(condition.merge(session_id: nil)).limit(batch_size).update_all(
          session_id: session_id,
          claimed_at: current_time,
          updated_at: current_time
        )
        
        total_claimed += claimed_count
        
        # バッチサイズ未満なら全て処理完了
        break if claimed_count < batch_size
        
      rescue ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout => e
        if retry_count < max_retries - 1
          backoff_seconds = calculate_backoff_seconds(retry_count)
          Rails.logger.warn("[#{name}] Deadlock detected during claim, retrying in #{backoff_seconds}s (attempt #{retry_count + 1}/#{max_retries})")
          sleep(backoff_seconds)
          next
        else
          Rails.logger.error("[#{name}] Max retries exceeded for claim operation: #{e.message}")
          raise
        end
      end
    end
    
    total_claimed
  end
  private_class_method :claim_in_batches

  # データベース claim 操作用の短時間リトライ（1秒間隔で最大5回）
  def self.calculate_backoff_seconds(retry_count)
    1  # 1秒間隔で統一（データベースロック競合の解決用）
  end
  private_class_method :calculate_backoff_seconds

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
    joins('LEFT JOIN delivery_responses ON mail_queues.id = delivery_responses.mail_queue_id')
      .where('mail_queues.session_id IS NOT NULL')
      .where('delivery_responses.id IS NULL')
  end

  # 結果がないレコードを返します。
  # このメソッドは単に、関連する DeliveryResponse にレコードが存在しない MailQueue(s) を返します。
  def self.undelivered
    where.missing(:delivery_responses)
  end

  private
    def set_timer_at_if_blank
      if timer_at.blank?
        self.timer_at = Time.current
      end
    end

  public
end
