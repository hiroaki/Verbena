namespace :verbena do
  namespace :delivery do
    desc '直近の配送がステータス4xxであったメッセージを再送キューに入れる'
    task :prepare_retry => :environment do |_task, _args|
      puts "Searching for retryable messages (last status 4xx)..."
      count = 0

      # 全レコードをスキャンするのは非効率ですが、メンテナンス用タスクのため許容します。
      # 本来は delivery_responses 側から検索すべきですが、最新ステータスの判定が必要なため
      # 親から辿っています。
      # TODO: 将来の効率化のため、以下の改善を検討:
      # - SQL条件で絞り込み可能なように、MailQueueに最新のdelivery_statusカラムを追加（例: 4xx, 5xx, success）。
      # - または、delivery_responsesテーブルから直接クエリ（JOINやサブクエリで最新ステータスを取得）。
      # - 大規模データセット向けに、プログレスインジケータ（例: 100件ごとにドット表示）を追加。
      MailQueue.find_each do |mq|
        last_response = mq.delivery_responses.order(created_at: :desc).first
        if last_response&.status.to_s.start_with?('4')
          DeliveryJob.perform_later(mq.id)
          count += 1
          print "."
        end
      end
      puts "\nEnqueued #{count} #{count == 1 ? 'job' : 'jobs'} for retry."
    end

    desc '配送結果が無いメッセージを配送キューに入れる'
    task :reset_undelivered, [:older_than_hours] => :environment do |_task, args|
      older_than_hours = (args[:older_than_hours] || 24).to_i
      time_threshold = older_than_hours.hours.ago

      puts "Searching for undelivered messages older than #{older_than_hours} hours (before #{time_threshold})..."
      count = 0

      MailQueue.where(timer_at: ..time_threshold).where.missing(:delivery_responses).find_each do |mq|
        DeliveryJob.perform_later(mq.id)
        count += 1
        print "."
      end
      puts "\nEnqueued #{count} #{count == 1 ? 'job' : 'jobs'} for undelivered."
    end
  end
end
