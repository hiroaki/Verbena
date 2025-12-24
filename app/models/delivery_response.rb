class DeliveryResponse < ApplicationRecord
  belongs_to :mail_queue

  # mail_queue_id ごとのグループについて、
  # - 最初の配信試行（最古の responded_at）から time_limit_seconds 以内であり
  # - 最新の配信結果の status が 4xx である
  # ものについて、その最新の DeliveryResponse の配列 (Array) を返します。
  #
  # 返される DeliveryResponse のリストにひもづく各 MailQueue は、
  # まだ再送信猶予時間内にあり、再送信を試みる候補となります。
  def self.last_status_4xx_within_time_limit(time_limit_seconds = 72.hours)
    unless time_limit_seconds.is_a?(Integer) || time_limit_seconds.is_a?(ActiveSupport::Duration)
      raise ArgumentError, 'time_limit_seconds must be an Integer or ActiveSupport::Duration'
    end
    seconds = time_limit_seconds.to_i
    raise ArgumentError, 'time_limit_seconds must be positive' if seconds <= 0

    boundary_time = Time.current - seconds

    DeliveryResponse.find_by_sql([<<-SQL2, boundary_time])
      SELECT T0.* FROM delivery_responses AS T0
      INNER JOIN (
        SELECT
          mail_queue_id,
          MAX(responded_at) AS latest,
          MIN(responded_at) AS earliest
        FROM delivery_responses
        GROUP BY mail_queue_id
      ) AS agg
        ON T0.mail_queue_id = agg.mail_queue_id
        AND T0.responded_at = agg.latest
      WHERE T0.status LIKE '4__'
        AND agg.earliest > ?
    SQL2
  end
end
