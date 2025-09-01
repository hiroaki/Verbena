class MailQueue < ApplicationRecord
  # レコードを予約（ engage ）しようとした場合に、
  # 指定した session_id のレコードが既に存在する場合に投げる例外
  EngageByNotNewSessionError = Class.new(StandardError)

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
  # session_id のセッション用に予約します。
  # 指定した session_id のレコードが存在する場合は例外を投げます。
  def self.engage_by_timer!(session_id)
    engage!(session_id, timer_at: ..Time.current)
  end

  # 一度も処理されていないレコードの中で、 id のレコードを、
  # session_id のセッション用に予約します。
  # 指定した session_id のレコードが存在する場合は例外を投げます。
  def self.engage_by_id!(session_id, id)
    engage!(session_id, id: id)
  end

  # 指定の condition の条件を満たすレコードを、 session_id のセッション用に予約します。
  # 影響を受けた行数（ update_all の戻り値）を返します。
  def self.engage!(session_id, condition)
    unless session_id.present?
      raise ArgumentError, 'The 1st argument "session_id" is not given'
    end

    if 0 < where(session_id: session_id).count
      raise EngageByNotNewSessionError
    else
      where(condition.merge(session_id: nil)).update_all(session_id: session_id, updated_at: Time.current)
    end
  end
  private_class_method :engage!

  # session_id のセッション用に予約されたレコードを返します。
  def self.engaged(session_id)
    where(session_id: session_id)
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
