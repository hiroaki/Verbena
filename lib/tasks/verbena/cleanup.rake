namespace :verbena do
  namespace :cleanup do
    desc 'Delete mail_queues and related records older than one month after delivery'
    task :monthly, [:dry] => :environment do |_task, args|
      begin
        service = Verbena::CleanupService.monthly(dry_run: Verbena::ServiceBase.truthy?(args[:dry]))
        report(service.cleanup)
      rescue StandardError => e
        $stderr.puts "ERROR: monthly failed: #{e.class}: #{e.message}"
        Kernel.exit(1)
      end
    end

    desc 'Delete mail_queues and related records older than one week after delivery'
    task :weekly, [:dry] => :environment do |_task, args|
      begin
        service = Verbena::CleanupService.weekly(dry_run: Verbena::ServiceBase.truthy?(args[:dry]))
        report(service.cleanup)
      rescue StandardError => e
        $stderr.puts "ERROR: weekly failed: #{e.class}: #{e.message}"
        Kernel.exit(1)
      end
    end

    desc 'Delete mail_queues and related records older than one day after delivery'
    task :daily, [:dry] => :environment do |_task, args|
      begin
        service = Verbena::CleanupService.daily(dry_run: Verbena::ServiceBase.truthy?(args[:dry]))
        report(service.cleanup)
      rescue StandardError => e
        $stderr.puts "ERROR: daily failed: #{e.class}: #{e.message}"
        Kernel.exit(1)
      end
    end

    desc 'Delete delivered mail_queues and related records'
    task :now, [:dry] => :environment do |_task, args|
      begin
        service = Verbena::CleanupService.new(dry_run: Verbena::ServiceBase.truthy?(args[:dry]))
        report(service.cleanup)
      rescue StandardError => e
        $stderr.puts "ERROR: now failed: #{e.class}: #{e.message}"
        Kernel.exit(1)
      end
    end

    desc 'Run cleanup based on TTL setting (VERBENA_CLEANUP_TTL_DAYS) with dry option'
    task :by_ttl, [:dry] => :environment do |_task, args|
      begin
        service = Verbena::CleanupService.by_ttl(dry_run: Verbena::ServiceBase.truthy?(args[:dry]))
        report(service.cleanup)
      rescue StandardError => e
        $stderr.puts "ERROR: by_ttl failed: #{e.class}: #{e.message}"
        Kernel.exit(1)
      end
    end
  end

  def report(result)
    Rails.logger.info("[cleanup] mail_queues=#{result[:mail_queues]} eml_sources=#{result[:eml_sources]}")
    puts "mail_queues=#{result[:mail_queues]} eml_sources=#{result[:eml_sources]}"
  end
end
