# Provides robust email delivery with failsafe for worker crashes/stalls.
#
# Concurrency & Safety Rationale:
# 1. Manual Recovery for Stuck Jobs: If a worker crashes while `processing`, the
#    `locked_until` timestamp will expire. To prevent mass double-delivery events
#    (e.g., during network latency spikes), we do NOT automatically recover.
#    Instead, we mark the job as 'failed' (via exception) to alert operators.
# 2. Risk Mitigation: `locked_until` (default 300s) acts as a safety buffer
#    against SMTP timeouts (30-60s).
# 3. State Integrity: We use `attempts_count` in conditional updates to ensure
#    that even if double delivery occurs, the slow (zombie) worker cannot
#    overwrite the final status (e.g. `succeeded`) recorded by the valid worker.
class DeliveryJob < ApplicationJob
  queue_as :default

  # Error raised when a lock has expired but the job is stuck in processing.
  # We fail fast to prevent double delivery.
  StuckLockError = Class.new(StandardError)

  retry_on(*Verbena::RetryableErrors.retryable_errors, wait: :exponentially_longer, attempts: -> { Verbena::Settings.delivery_max_retries })

  def self.retryable_error?(exception)
    Verbena::RetryableErrors.retryable_error?(exception)
  end

  def perform(mail_queue_id)
    mail_queue = MailQueue.find_by(id: mail_queue_id)
    unless mail_queue
      # If the MailQueue record cannot be found, log a warning to aid debugging.
      # Records may be deleted while jobs are queued; emitting a warning helps
      # operators detect and investigate missing records.
      logger.warn("DeliveryJob: mail_queue not found (id=#{mail_queue_id}) - possibly deleted while queued; job_id=#{job_id}")
      return
    end

    # Lock only for the state transition. We intentionally release the lock
    # before calling DeliveryService (external I/O) to avoid holding DB locks
    # during network calls. Subsequent runs will see delivery_status=processing
    # and skip, so double-send is avoided without long-held locks.
    mail_queue.with_lock do
      # Avoid double execution if already processed/processing by another worker
      if mail_queue.delivery_status == 'succeeded'
        logger.info("DeliveryJob: Skipped mail_queue (id=#{mail_queue_id}) because status is already 'succeeded'")
        return
      end

      if mail_queue.delivery_status == 'processing'
        if mail_queue.locked_until && mail_queue.locked_until > Time.current
          logger.info("DeliveryJob: Skipped mail_queue (id=#{mail_queue_id}) because status is 'processing' and lock is active until #{mail_queue.locked_until}")
          return
        else
          # Lock expired. FAIL FAST intentionally.
          # We raise an exception to trigger the rescue block below, which will:
          # 1. Update status to 'failed' (so it doesn't get stuck in 'processing')
          # 2. Alert operators via standard error monitoring
          msg = "DeliveryJob: Stuck MailQueue detected (id=#{mail_queue_id}). " \
                "Status is 'processing' but lock expired at #{mail_queue.locked_until}. " \
                "Marking as failed to prevent double-delivery risks."
          logger.error(msg)
          raise StuckLockError, msg
        end
      end

      attempt_number = mail_queue.attempts_count + 1
      base_ttl = Verbena::Settings.delivery_lock_ttl_seconds
      max_ttl = Verbena::Settings.delivery_lock_max_seconds
      ttl_seconds = [base_ttl * attempt_number, max_ttl].min
      mail_queue.update!(
        delivery_status: :processing,
        attempts_count: attempt_number,
        last_attempted_at: Time.current,
        locked_until: Time.current + ttl_seconds
      )
    end

    # Use the job_id as the job_id for logging/tracking purposes
    Verbena::DeliveryService.new(job_id: job_id).perform_one(mail_queue)

    # Conditional update: only flip to succeeded if no one changed the status
    # after we set it to processing. This avoids overwriting a newer status.
    # We also check attempts_count to ensure we don't overwrite if another worker has taken over.
    result = MailQueue.where(id: mail_queue.id, delivery_status: :processing, attempts_count: mail_queue.attempts_count)
                      .update_all(delivery_status: :succeeded, locked_until: nil, updated_at: Time.current)

    if result.zero?
      logger.warn("DeliveryJob: Race condition detected on success. MailQueue(#{mail_queue.id}) was modified by others.")
    end
  rescue *Verbena::RetryableErrors.retryable_errors => ex
    # Expected retryable errors: mark retrying and re-raise to let ActiveJob retry_on handle it.
    result = MailQueue.where(id: mail_queue.id, delivery_status: :processing, attempts_count: mail_queue.attempts_count)
                      .update_all(delivery_status: :retrying, locked_until: nil, updated_at: Time.current)

    if result.zero?
      logger.warn("DeliveryJob: Race condition detected on retryable error. MailQueue(#{mail_queue.id}) was modified by others. Skip status update.")
    end

    raise ex
  rescue => ex
    # Non-retryable errors: mark failed but let the exception propagate for visibility.
    result = MailQueue.where(id: mail_queue.id, delivery_status: :processing, attempts_count: mail_queue.attempts_count)
                      .update_all(delivery_status: :failed, locked_until: nil, updated_at: Time.current)

    if result.zero?
      logger.warn("DeliveryJob: Race condition detected on non-retryable error. MailQueue(#{mail_queue.id}) was modified by others. Skip status update.")
    end

    raise ex
  end
end
