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

      revoked_count = 0
      relation.find_in_batches(batch_size: batch_size) do |batch|
        batch.each do |tok|
          begin
            tok.revoke!(Time.current)
            revoked_count += 1
          rescue StandardError => e
            logger.warn(structured_log(
              event: 'token.revoke_failed',
              level: 'warn',
              session_id: nil,
              mail_queue_id: nil,
              message: "revoke failed id=#{tok.id} error=#{e.class}:#{e.message}",
              message_id: tok.id,
              error: e.message
            ))
          end
        end
      end
      revoked_count
    end
  end
end
