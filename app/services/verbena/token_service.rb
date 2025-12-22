module Verbena
  class TokenService < ServiceBase
    DEFAULT_BATCH_SIZE = 1000

    # Revoke expired tokens that are not yet revoked.
    # Returns the number of tokens revoked (or would be revoked in dry run).
    #
    # Each token is revoked individually with `revoke!` to preserve callbacks,
    # validations, and per-token error handling, which is useful for auditing.
    # For this application, the tokens table is small, so batch processing is
    # optional and overhead is minimal.
    def revoke_expired(dry_run: false, batch_size: DEFAULT_BATCH_SIZE)
      relation = Token.expired
      return relation.count if dry_run

      total = 0
      relation.find_in_batches(batch_size: batch_size) do |batch|
        batch.each do |tok|
          begin
            tok.revoke!(Time.current)
            total += 1
          rescue StandardError => e
            logger.warn("[TokenService] revoke failed id=#{tok.id} error=#{e.class}:#{e.message}")
          end
        end
      end
      total
    end
  end
end
