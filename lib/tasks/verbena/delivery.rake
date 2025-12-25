namespace :verbena do
  namespace :delivery do
    desc 'mail_queue のメッセージを配送する(タイマー制御)'
    task by_timer: :environment  do |_task, args|
      begin
        Verbena::DeliveryService.new.perform_by_timer
      rescue => e
        $stderr.puts "ERROR: by_timer failed: #{e.class}: #{e.message}"
        Kernel.exit(1)
      end
    end

    desc 'mail_queue のメッセージを配送する(ID指定)'
    task by_ids: :environment  do |_task, args|
      begin
        Verbena::DeliveryService.new.perform_by_mail_queue_id(args.extras)
      rescue => e
        $stderr.puts "ERROR: by_ids failed: #{e.class}: #{e.message}"
        Kernel.exit(1)
      end
    end

    desc 'session_id の処理のうちで直近の配送がステータス4xxであったメッセージを再送可能状態にする'
    task :prepare_retry, [:session_id] => :environment do |_task, args|
      begin
        count = Verbena::DeliveryService.with_session(args[:session_id]).prepare_to_retry_for_session(args.extras.first)
        puts "prepare_retry: reset #{count} mail_queues for session_id=#{args[:session_id]}"
      rescue => e
        $stderr.puts "ERROR: prepare_retry failed: #{e.class}: #{e.message}"
        Kernel.exit(1)
      end
    end

    desc 'session_id の処理のうちで配送結果が無いメッセージを再送可能状態にする'
    task :reset_undelivered, [:session_id] => :environment do |_task, args|
      begin
        count = Verbena::DeliveryService.with_session(args[:session_id]).prepare_to_retry_undelivered
        puts "reset_undelivered: reset #{count} mail_queues for session_id=#{args[:session_id]}"
      rescue => e
        $stderr.puts "ERROR: reset_undelivered failed: #{e.class}: #{e.message}"
        Kernel.exit(1)
      end
    end
  end
end
