namespace :verbena do
  namespace :delivery do
    desc 'mail_queue のメッセージを配送する(タイマー制御)'
    task by_timer: :environment  do |_task, args|
      Verbena::DeliveryService.new.perform_by_timer
    end

    desc 'mail_queue のメッセージを配送する(ID指定)'
    task by_ids: :environment  do |_task, args|
      Verbena::DeliveryService.new.perform_by_mail_queue_id(args.extras)
    end

    desc 'session_id の処理のうちで直近の配送がステータス4xxであったメッセージを再送可能状態にする'
    task :prepare_retry, [:session_id] => :environment do |_task, args|
      timelimit = args.extras.first
      Verbena::DeliveryService.new(args).prepare_to_retry_for_session(timelimit)
    end

    desc 'session_id の処理のうちで配送結果が無いメッセージを再送可能状態にする'
    task :reset_undelivered, [:session_id] => :environment do |_task, args|
      Verbena::DeliveryService.new(args).prepare_to_retry_undelivered
    end
  end
end
