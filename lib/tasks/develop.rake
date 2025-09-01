namespace :develop do
  desc 'メッセージをログに出力する：例 rails develop:logit["hello"]'
  task :logit, [:message, :level] => :environment  do |_task, args|
    message = args[:message]
    level = args[:level] || :info
    Rails.logger.send(level, message)
  end

  desc 'mail_queue.session_id を NULL にする'
  task clear_session_id: :environment  do |_task, args|
    session_ids = args.extras

    if session_ids.empty?
      MailQueue.update_all(session_id: nil)
    else
      MailQueue.where(session_id: session_ids).update_all(session_id: nil)
    end
  end
end
