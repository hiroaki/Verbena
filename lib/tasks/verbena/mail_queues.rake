namespace :verbena do
  namespace :mail_queues do
    desc 'mail_queues に eml ファイルの内容を登録する'
    task :add, [:eml] => :environment do |_task, args|
      begin
        mail_queues = Verbena::MailQueuesService.new.create_mail_queues_from_file!(args[:eml])
        puts "Successfully added #{mail_queues.size} mail_queue(s) from #{args[:eml]}"
      rescue => e
        $stderr.puts "ERROR: add failed: #{e.class}: #{e.message}"
        Kernel.exit(1)
      end
    end

    desc 'mail_queues に eml, envelope_from, envelope_to を登録する'
    task :add_raw, [:eml, :envelope_from, :envelope_to] => :environment do |_task, args|
      begin
        mail_queue = Verbena::MailQueuesService.new.create_mail_queue_from_file_with_envelope!(args[:eml], args[:envelope_from], args[:envelope_to], args.extras.first.presence)
        puts "Successfully added mail_queue (#{mail_queue.id}) with envelope from #{args[:envelope_from]} to #{args[:envelope_to]}"
      rescue => e
        $stderr.puts "ERROR: add_raw failed: #{e.class}: #{e.message}"
        Kernel.exit(1)
      end
    end

    desc 'mail_queues から指定した id のレコードを削除する'
    task :delete, [:mail_queue_id] => :environment do |_task, args|
      begin
        Verbena::MailQueuesService.new.destroy_mail_queue_by_id!(args[:mail_queue_id])
        puts "Deleted mail_queue id=#{args[:mail_queue_id]}"
      rescue => e
        $stderr.puts "ERROR: delete failed: #{e.class}: #{e.message}"
        Kernel.exit(1)
      end
    end
  end
end
