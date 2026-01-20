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
      # - MailQueue に最新の delivery_status カラムを追加して SQL 条件で絞り込む（例: 4xx, 5xx, success）。
      #   - このカラムにインデックスを貼ることで大量データでも高速に検索できる（例: add_index :mail_queues, :latest_delivery_status）。
      # - delivery_responses テーブルから直接クエリ（JOIN やサブクエリで最新ステータスを取得）。
      #   - 必要なら last_response を保持するマテリアライズドビューを作成し、定期的に REFRESH することで検索を高速化する案も有効。
      # - delivery_responses 側に（mail_queue_id, responded_at DESC）を利用したインデックスを検討する（例: add_index :delivery_responses, [:mail_queue_id, :responded_at]）。
      # - 大規模データセット向けに、プログレスインジケータ（100件ごとにドット表示）を追加。
      #
      # 意図的な選択: 間隔は 100 件で固定しています。間隔を可変にするとランタイム設定が増え、
      # 利点が小さいと判断しました。設定項目を増やしたくないため固定としています。
      # 運用上の要望が出た場合に限り設定化を検討してください。
      processed = 0
      MailQueue.find_each do |mq|
        processed += 1
        print "." if (processed % 100).zero?

        last_response = mq.delivery_responses.order(responded_at: :desc).first
        if last_response&.status.to_s.start_with?('4')
          DeliveryJob.perform_later(mq.id)
          count += 1
        end
      end
      puts "\nEnqueued #{count} #{count == 1 ? 'job' : 'jobs'} for retry."
    end

    desc '配送結果が無いメッセージを配送キューに入れる'
    task :reset_undelivered, [:older_than_hours] => :environment do |_task, args|
      older_than_arg = args[:older_than_hours]
      older_than_hours =
        if older_than_arg.nil? || older_than_arg.to_s.strip.empty?
          24
        elsif older_than_arg.to_s =~ /\A\d+\z/
          older_than_arg.to_i
        else
          raise ArgumentError, "older_than_hours must be a non-negative integer number of hours, got: #{older_than_arg.inspect}"
        end
      time_threshold = older_than_hours.hours.ago

      puts "Searching for undelivered messages older than #{older_than_hours} hours (before #{time_threshold})..."
      count = 0

      # Print a dot every 100 processed records to indicate progress.
      processed = 0
      MailQueue.where(timer_at: ..time_threshold).where.missing(:delivery_responses).find_each do |mq|
        processed += 1
        print "." if (processed % 100).zero?

        DeliveryJob.perform_later(mq.id)
        count += 1
      end
      puts "\nEnqueued #{count} #{count == 1 ? 'job' : 'jobs'} for undelivered."
    end
  end
end
