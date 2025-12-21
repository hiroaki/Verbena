class MailQueue < ApplicationRecord
  # レコードを専有取得（ claim ）しようとした場合に、
  # 指定した session_id のレコードが既に存在する場合に投げる例外
  ClaimByNotNewSessionError = Class.new(StandardError)

  belongs_to :eml_source
  has_many :delivery_responses, dependent: :destroy

  validates :timer_at, presence: true
  validates :envelope_to, presence: true

  # 永続化するには timer_at は必須ですが、部分 SELECT で timer_at カラムが欠けることがあるため、
  # その場合はコールバックを実行しないようにします。
  after_initialize :set_timer_at_if_blank, if: -> { has_attribute?(:timer_at) }

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

  # Processes claims in small batches with deadlock retry.
  # Uses ID-first approach (pluck then update by ID set) for portability and race-safety.
  # See CLAIM_HARDENING.md "Implementation Details" for rationale.
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
        # Guard with session_id: nil to prevent concurrent processes from overwriting claims
        claimed_count = where(id: ids, session_id: nil).update_all(
          session_id: session_id,
          claimed_at: current_time,
          updated_at: Time.current
        )

        total_claimed += claimed_count

        # If we fetched fewer than batch_size ids, we've exhausted available rows
        break if ids.length < batch_size

        # reset retry counter after a successful batch
        retries = 0
      rescue ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout => e
        if retries < max_retries
          backoff_seconds = calculate_backoff_seconds(retries)
          Rails.logger.warn("[#{name}] Deadlock detected during claim, retrying in #{backoff_seconds}s (attempt #{retries + 1}/#{max_retries})")
          sleep(backoff_seconds)
          retries += 1
          next
        else
          # Max retries exceeded: Log error and re-raise for manual intervention.
          # See CLAIM_HARDENING.md "Max Retries Exceeded: Recovery Procedures" for operational guidance.
          Rails.logger.error("[#{name}] Max retries exceeded for claim operation for session_id=[#{session_id}]: #{e.message}")
          raise
        end
      end
    end

    total_claimed
  end
  private_class_method :claim_in_batches

  # デッドロック検知やロックタイムアウトの際のリトライまでの待ち時間秒
  def self.calculate_backoff_seconds(retry_count)
    # 指数バックオフ（ジッタ付き）によるリトライ待ち時間の実装
    # base/cap は設定経由で取得可能（Verbena::Settings）
    base = Verbena::Settings.claim_backoff_base_seconds
    cap  = Verbena::Settings.claim_backoff_cap_seconds

    # retry_count に応じて指数的に増加（cap を超えない）
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
  def self.claim_max_retries
    Verbena::Settings.claim_max_retries
  end
  private_class_method :claim_max_retries

  # claim 処理のバッチサイズを取得
  def self.claim_batch_size
    Verbena::Settings.in_batches_config[:of] || 20
  end
  private_class_method :claim_batch_size

  # session_id のセッション用に専有取得（claim）されたレコードを返します。
  def self.claimed(session_id)
    where(session_id: session_id)
  end

  # スタック（古い claim で未配送）のレコードを返すリレーション
  def self.stale_claims_relation(older_than: 1.hour.ago)
    where(claimed_at: ..older_than)
      .where.not(session_id: nil)
      .where.missing(:delivery_responses)
  end

  # NOTE: Stale claim release is orchestrated in Verbena::MailQueuesService.

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
      if timer_at.blank?
        self.timer_at = Time.current
      end
    end

  public
end
