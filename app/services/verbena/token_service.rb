module Verbena
  class TokenService < ServiceBase
    DEFAULT_BATCH_SIZE = 1000

    # Revoke tokens whose expires_at has passed and are not yet revoked.
    # Returns the number of tokens targeted (dry run) or revoked (executed).
    def revoke_expired(dry_run: false, batch_size: DEFAULT_BATCH_SIZE)
      relation = Token.expired
      return relation.count if dry_run

      total = 0
      relation.find_in_batches(batch_size: batch_size) do |batch|
        batch.each do |tok|
          begin
            tok.revoke!(Time.current)
            total += 1
          rescue => e
            logger.warn("[TokenService] revoke failed id=#{tok.id} error=#{e.class}:#{e.message}")
          end
        end
      end
      total
    end
  end
end
