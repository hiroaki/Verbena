namespace :verbena do
  namespace :mail_queues do
    # Helper: parse key:value extras passed to Rake tasks.
    # Accepted extras format: `key:value` entries in any order.
    # Recognized keys:
    # - `token`: API token key (overrides `VERBENA_TOKEN` env var)
    # - `timer_at` or `at`: ISO-8601 / parsable time string used to schedule delivery
    # Other entries are ignored. Entries without `:` are ignored to preserve
    # backward-compatibility with positional args.
    def parse_extras(args = nil)
      return {} unless args && args.extras
      args.extras.each_with_object({}) do |entry, memo|
        unless entry.include?(':')
          $stderr.puts "WARNING: Ignoring extra argument without key:value format (expected e.g., token:KEY or timer_at:TIME)"
          next
        end
        k, v = entry.split(':', 2)
        memo[k.to_s.downcase] = v
      end
    end

    desc 'mail_queues に eml ファイルの内容を登録する'
    task :add, [:eml] => :environment do |task, args|
      begin
        extras = parse_extras(args)
        token = Token.authenticate(extras['token'] || ENV['VERBENA_TOKEN'])
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
        extras = parse_extras(args)
        token = Token.authenticate(extras['token'] || ENV['VERBENA_TOKEN'])
        unless token
          raise ArgumentError, 'Valid token is required. Provide via VERBENA_TOKEN env var (or token:KEY argument).'
        end

        timer_value = extras['timer_at'] || extras['at']
        timer_at = nil
        if timer_value.present?
          begin
            timer_at = Time.zone.parse(timer_value)
          rescue StandardError
            raise ArgumentError, "Invalid timer_at format: #{timer_value}"
          end
        end

        mail_queue = Verbena::MailQueuesService.new(token: token).create_mail_queue_from_file_with_envelope!(args[:eml], args[:envelope_from], args[:envelope_to], timer_at)
        puts "Successfully added mail_queue (#{mail_queue.id}) with envelope from #{args[:envelope_from]} to #{args[:envelope_to]} (Token: #{token.label})"
      rescue StandardError => e
        $stderr.puts "ERROR: #{task.name} failed: #{e.class}: #{e.message}"
        Kernel.exit(1)
      end
    end

    desc 'mail_queues から指定した id のレコードを削除する'
    task :delete, [:mail_queue_id] => :environment do |task, args|
      begin
        extras = parse_extras(args)
        token = Token.authenticate(extras['token'] || ENV['VERBENA_TOKEN'])
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
