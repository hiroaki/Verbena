class DeliveryResponse < ApplicationRecord
  belongs_to :mail_queue

  # 各 mail_queue_id ごとのレコード群が次の条件を満たす場合に、
  # その各レコード群の最新のレコードをリストで返します。
  # - 最古の responded_at 時刻から time_limit_string 時間がまだ経過していない
  # - 最新のレコードの status が 4xx である
  #
  # 別の言い方： DeliveryResponse を mail_queue_id ごとのグループにした時、
  # それぞれの最新のレコードの status が 4xx であるものを集めたリストを結果として得ますが、
  # ただしそれぞれのグループの最古のレコードの responded_at 時刻から time_limit_string 時間が経過していた場合は、
  # 結果のリストには含めません。
  #
  # 例）たとえば time_limit_string = '72:00:00' の場合、
  # ある mail_queue_id に関係するレスポンスのうちで最古のものの、
  # その responded_at の時刻から 72 時間以上を経過していた場合、
  # その mail_queue_id に関連するデータは結果に含まれません。
  #
  # TODO:
  #   DB と Rails とのタイムゾーンを合わせなければいけません。
  #   また NOW() を使うと、 rspec で時刻を固定するテストが実施できなくなるので、使わないようにします。
  #   タイムゾーンは次の前提です：
  #   - DB のタイムゾーン = システムのタイムゾーン = JST
  #   - Rails のタイムゾーン(ActiveRecord 含む) = JST
  #
  # WARN:
  #   - SQL の中の HAVING... のところで、 #strftime を使っています。
  #     これについては #to_fs(:db) を使わないでください。 UTC の時刻になってしまいます。
  def self.last_status_4xx_within_time_limit(time_limit_string = '72:00:00') # 初期値 72時間=3日間
    DeliveryResponse.find_by_sql(<<-SQL2
      SELECT * FROM delivery_responses AS T0
      INNER JOIN (
        SELECT
          mail_queue_id,
          MAX(responded_at) AS latest
        FROM delivery_responses
        GROUP BY mail_queue_id
      ) AS T3
      ON T0.responded_at = T3.latest AND T0.mail_queue_id = T3.mail_queue_id
      WHERE T0.mail_queue_id IN (
        SELECT T1.mail_queue_id FROM delivery_responses AS T1
          INNER JOIN (
            SELECT
              id,
              mail_queue_id,
              ADDTIME(MIN(responded_at), '#{time_limit_string}') AS limittime
            FROM delivery_responses
            GROUP BY mail_queue_id
            HAVING "#{Time.current.strftime("%Y-%m-%d %H:%M:%S")}" < limittime
          ) AS T2
          ON T1.mail_queue_id = T2.mail_queue_id
        GROUP BY T1.mail_queue_id
      )
      AND T0.status LIKE "4__"
    SQL2
    )
  end
end
