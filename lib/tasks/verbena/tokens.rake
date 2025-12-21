namespace :verbena do
  namespace :tokens do
    desc 'Revoke expired tokens (sets revoked_at). Usage: rake verbena:tokens:revoke_expired[dry]'
    task :revoke_expired, [:mode] => :environment do |t, args|
      mode = args[:mode].to_s
      dry_run = mode == 'dry'

      service = Verbena::TokenService.new

      if dry_run
        count = service.revoke_expired(dry_run: true)
        puts "[verbena:tokens:revoke_expired] Dry run: #{count} tokens would be revoked"
      else
        total = service.revoke_expired(dry_run: false)
        puts "[verbena:tokens:revoke_expired] Revoked #{total} tokens"
      end
    end
  end
end
