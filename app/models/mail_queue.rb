class MailQueue < ApplicationRecord
  belongs_to :eml_source
  has_many :delivery_responses, dependent: :destroy

  validates :timer_at, presence: true
  validates :envelope_to, presence: true

  # 永続化するには timer_at は必須ですが、部分 SELECT で timer_at カラムが欠けることがあるため、
  # その場合はコールバックを実行しないようにします。
  after_initialize :set_timer_at_if_blank, if: -> { has_attribute?(:timer_at) }

  delegate :eml, to: :eml_source

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

