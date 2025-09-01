namespace :verbena do
  namespace :mail_queues do
    desc 'mail_queues に eml ファイルの内容を登録する'
    task :add, [:eml] => :environment do |_task, args|
      eml = File.read(args[:eml])
      Verbena::MailQueuesService.new.create_mail_queues_by_eml!(eml)
    end

    desc 'mail_queues に eml, envelope_from, envelope_to を登録する'
    task :add_raw, [:eml, :envelope_from, :envelope_to] => :environment do |_task, args|
      eml = File.read(args[:eml])
      envelope_from = args[:envelope_from]
      envelope_to = args[:envelope_to]
      timer_at = args.extras.first.presence || Time.current
      Verbena::MailQueuesService.new.create_mail_queue_with_envelope!(eml, envelope_from, envelope_to, timer_at)
    end

    desc 'mail_queues から指定した id のレコードを削除する'
    task :delete, [:mail_queue_id] => :environment do |_task, args|
      Verbena::MailQueuesService.new.destroy_mail_queue_by_id!(args[:mail_queue_id])
    end
  end
end
