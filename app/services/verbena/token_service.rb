module Verbena
  class TokenService < ServiceBase
    DEFAULT_BATCH_SIZE = 1000

    # Returns the number of tokens that would be revoked (dry-run count).
    def expired_count
      revoke_expired(dry_run: true)
    end

    # Perform the revocation and return the number revoked. This is a
    # clearer, explicit destructive API for callers that actually want to
    # mutate state (rake tasks, operators, etc.). Internally delegates to
    # the existing `revoke_expired` implementation.
    def revoke_expired!
      revoke_expired(dry_run: false)
    end

    private

    # Revoke expired tokens that are not yet revoked.
    # Returns the number of tokens revoked (or would be revoked in dry run).
    #
    # Each token is revoked individually with `revoke!` to preserve callbacks,
    # validations, and per-token error handling, which is useful for auditing.
    # For this application, the tokens table is small, so batch processing is
    # optional and overhead is minimal.
    def revoke_expired(dry_run: false, batch_size: DEFAULT_BATCH_SIZE)
      rel = expired_relation
      return rel.count if dry_run

      revoked_count = 0
      rel.find_in_batches(batch_size: batch_size) do |batch|
        batch.each do |tok|
          begin
            tok.revoke!(Time.current)
            revoked_count += 1
          rescue StandardError => e
            logger.warn(structured_log(
              event: 'token.revoke_failed',
              level: 'warn',
              job_id: nil,
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

    # Centralize how we build the relation of tokens we intend to operate on.
    # This ensures `expired_count` and revocation use identical selection
    # logic and avoids divergence if the criteria change.
    def expired_relation
      Token.expired
    end
  end
end
