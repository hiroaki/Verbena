namespace :verbena do
  namespace :mail_queues do
    # Helper: obtain and authenticate token from ENV or task extras
    def fetch_token_from(args = nil)
      token_key = if args && args.extras
                    ENV['VERBENA_TOKEN'] || args.extras.find { |arg| arg.start_with?('token:') }&.split(':', 2)&.last
                  else
                    ENV['VERBENA_TOKEN']
                  end

      # Return token or nil to let caller decide how to handle missing token.
      Token.authenticate(token_key)
    end

    desc 'mail_queues に eml ファイルの内容を登録する'
    task :add, [:eml] => :environment do |task, args|
      begin
        token = fetch_token_from(args)
        unless token
          raise ArgumentError, 'Valid token is required. Provide via VERBENA_TOKEN env var (or token:KEY argument).'
        end

        mail_queues = Verbena::MailQueuesService.new(token: token).create_mail_queues_from_file!(args[:eml])
        puts "Successfully added #{mail_queues.size} mail_queue(s) from #{args[:eml]} (Token: #{token.label})"
      rescue StandardError => e
        $stderr.puts "ERROR: #{task.name} failed: #{e.class}: #{e.message}"
        Kernel.exit(1)
      end
    end

    desc 'mail_queues に eml, envelope_from, envelope_to を登録する'
    task :add_raw, [:eml, :envelope_from, :envelope_to] => :environment do |task, args|
      begin
        token = fetch_token_from(args)
        unless token
          raise ArgumentError, 'Valid token is required. Provide via VERBENA_TOKEN env var (or token:KEY argument).'
        end

        mail_queue = Verbena::MailQueuesService.new(token: token).create_mail_queue_from_file_with_envelope!(args[:eml], args[:envelope_from], args[:envelope_to], args.extras.first.presence)
        puts "Successfully added mail_queue (#{mail_queue.id}) with envelope from #{args[:envelope_from]} to #{args[:envelope_to]} (Token: #{token.label})"
      rescue StandardError => e
        $stderr.puts "ERROR: #{task.name} failed: #{e.class}: #{e.message}"
        Kernel.exit(1)
      end
    end

    desc 'mail_queues から指定した id のレコードを削除する'
    task :delete, [:mail_queue_id] => :environment do |task, args|
      begin
        token = fetch_token_from(args)
        unless token
          raise ArgumentError, 'Valid token is required. Provide via VERBENA_TOKEN env var (or token:KEY argument).'
        end

        Verbena::MailQueuesService.new(token: token).destroy_mail_queue_by_id!(args[:mail_queue_id])
        puts "Deleted mail_queue id=#{args[:mail_queue_id]} (Subject to token ownership)"
      rescue StandardError => e
        $stderr.puts "ERROR: #{task.name} failed: #{e.class}: #{e.message}"
        Kernel.exit(1)
      end
    end
  end
end
