namespace :verbena do
  namespace :cleanup do
    desc '配送処理後、一ヶ月以上を経過した mail_queues と関連レコードを削除する'
    task :monthly, [:dry] => :environment do |_task, args|
      begin
        service = Verbena::CleanupService.monthly(dry_run: Verbena::ServiceBase.truthy?(args[:dry]))
        report(service.cleanup)
      rescue StandardError => e
        $stderr.puts "ERROR: monthly failed: #{e.class}: #{e.message}"
        Kernel.exit(1)
      end
    end

    desc '配送処理後、一週以上を経過した mail_queues と関連レコードを削除する'
    task :weekly, [:dry] => :environment do |_task, args|
      begin
        service = Verbena::CleanupService.weekly(dry_run: Verbena::ServiceBase.truthy?(args[:dry]))
        report(service.cleanup)
      rescue StandardError => e
        $stderr.puts "ERROR: weekly failed: #{e.class}: #{e.message}"
        Kernel.exit(1)
      end
    end

    desc '配送処理後、一日以上を経過した mail_queues と関連レコードを削除する'
    task :daily, [:dry] => :environment do |_task, args|
      begin
        service = Verbena::CleanupService.daily(dry_run: Verbena::ServiceBase.truthy?(args[:dry]))
        report(service.cleanup)
      rescue StandardError => e
        $stderr.puts "ERROR: daily failed: #{e.class}: #{e.message}"
        Kernel.exit(1)
      end
    end

    desc '配送処理が済んでいる mail_queues と関連レコードを削除する'
    task :now, [:dry] => :environment do |_task, args|
      begin
        service = Verbena::CleanupService.new(dry_run: Verbena::ServiceBase.truthy?(args[:dry]))
        report(service.cleanup)
      rescue StandardError => e
        $stderr.puts "ERROR: now failed: #{e.class}: #{e.message}"
        Kernel.exit(1)
      end
    end

    desc 'TTL 設定（VERBENA_CLEANUP_TTL_DAYS）に基づいてクリーンアップを実行（dry オプション対応）'
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
