class MailQueue < ApplicationRecord
  belongs_to :eml_source
  has_many :delivery_responses, dependent: :destroy

  # 配信ステータス:
  # - pending: 配信待ち。ジョブがまだ処理を開始していない初期状態。
  # - processing: 現在処理中。ジョブがロックを取り、配信処理を実行している状態。
  # - retrying: 再試行待ち。一時的なエラーにより再送が予定されている状態（ActiveJob のリトライ対象）。
  # - succeeded: 配信成功。少なくとも1件の `delivery_responses` が存在し、処理が完了した状態。
  # - failed: 配信失敗。再試行不可のエラーで処理が打ち切られた状態（手動対応や調査が必要）。
  # 補足:
  # - `attempts_count` は試行回数の追跡に使用されます。
  # - `last_attempted_at` は最後の試行日時を示します。
  # - `locked_until` は処理中の排他のために設定されます（処理が終了したら nil に戻します）。
  enum :delivery_status, {
    pending: 'pending',
    processing: 'processing',
    retrying: 'retrying',
    succeeded: 'succeeded',
    failed: 'failed'
  }, suffix: true

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

