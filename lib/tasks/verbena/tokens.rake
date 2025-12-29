namespace :verbena do
  namespace :tokens do
    desc 'Revoke expired tokens (sets revoked_at). Usage: rake verbena:tokens:revoke_expired[dry]'
    task :revoke_expired, [:dry] => :environment do |_task, args|
      begin
        dry_run = Verbena::ServiceBase.truthy?(args[:dry])

        service = Verbena::TokenService.new

        if dry_run
          count = service.expired_count
          puts "[verbena:tokens:revoke_expired] Dry run: #{count} tokens would be revoked"
        else
          revoked_count = service.revoke_expired!
          puts "[verbena:tokens:revoke_expired] Revoked #{revoked_count} tokens"
        end
      rescue StandardError => e
        $stderr.puts "ERROR: revoke_expired failed: #{e.class}: #{e.message}"
        Kernel.exit(1)
      end
    end
  end
end
