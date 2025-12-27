namespace :verbena do
  namespace :claim do
    desc 'Release stale claims (claimed but not delivered mail_queues)'
    task :release_stale, [:older_than_hours, :dry] => :environment do |_task, args|
      begin
        older_than_hours = Verbena::MailQueuesService.normalize_hours_arg(args[:older_than_hours])
        dry_run = truthy?(args[:dry])

        service = Verbena::MailQueuesService.new
        stale_count = service.release_stale_claims(older_than_hours: older_than_hours, dry_run: dry_run)

        hour_unit = 'hour'.pluralize(older_than_hours.round)
        if dry_run
          puts "DRY RUN: Would release #{stale_count} stale claims older than #{older_than_hours} #{hour_unit} (excluding delivered records)"
        else
          puts "Released #{stale_count} stale claims older than #{older_than_hours} #{hour_unit}"
        end
      rescue StandardError => e
        $stderr.puts "ERROR: release_stale failed: #{e.class}: #{e.message}"
        Kernel.exit(1)
      end
    end

    desc 'Show claimed but undelivered mail_queues (stuck detection)'
    task :show_stale => :environment do
      begin
        service = Verbena::MailQueuesService.new
        stale_records = service.show_stale_claims

        if stale_records.any?
          puts "Found #{stale_records.size} claimed but undelivered records:"
          puts "ID\tSession ID\tClaimed At\tEnvelope To\tAge"
          puts "-" * 80

          stale_records.each do |record|
            age_str = format_duration(record[:age_seconds])
            session_id_str = record[:session_id] ? "#{record[:session_id][0..8]}..." : "(none)"
            puts "#{record[:id]}\t#{session_id_str}\t#{record[:claimed_at]}\t#{record[:envelope_to]}\t#{age_str}"
          end
        else
          puts "No stale claimed records found."
        end
      rescue StandardError => e
        $stderr.puts "ERROR: show_stale failed: #{e.class}: #{e.message}"
        Kernel.exit(1)
      end
    end
  end

  # Rake helper methods (local to this file)
  BOOLEAN_TYPE ||= ActiveModel::Type::Boolean.new

  def truthy?(val)
    # Rails-native boolean casting: true => 1,true,t,on,yes | false => 0,false,f,off,no
    BOOLEAN_TYPE.cast(val).presence || false
  end

  # Format seconds as human-readable string.
  #
  # Examples:
  #   format_duration(0)      #=> "0s"
  #   format_duration(5)      #=> "5s"
  #   format_duration(65)     #=> "1m5s"
  #   format_duration(3661)   #=> "1h1m1s"
  #   format_duration(3600)   #=> "1h0m0s"
  #   format_duration(7322)   #=> "2h2m2s"
  def format_duration(seconds)
    return "0s" if seconds < 1

    # 秒単位に丸める（小数部は破棄）
    hours = (seconds / 3600).to_i
    minutes = ((seconds % 3600) / 60).to_i
    secs = (seconds % 60).to_i

    parts = []
    parts << "#{hours}h" if hours > 0
    parts << "#{minutes}m" if minutes > 0 || hours > 0
    parts << "#{secs}s"

    parts.join("")
  end
end