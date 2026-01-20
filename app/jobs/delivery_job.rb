class DeliveryJob < ApplicationJob
  queue_as :default

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

    mail_queue.with_lock do
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

    mail_queue.update!(delivery_status: :succeeded, locked_until: nil)
  rescue => ex
    status = Verbena::RetryableErrors.retryable_error?(ex) ? :retrying : :failed

    # Reload the record to ensure we operate on the latest DB state and avoid stale
    # in-memory attributes (especially if the error occurred during the initial
    # update! inside the lock). If the record no longer exists, log and skip.
    mq = MailQueue.find_by(id: mail_queue_id)
    if mq
      begin
        mq.update!(delivery_status: status, locked_until: nil)
      rescue => update_ex
        logger.error("DeliveryJob: failed to update mail_queue status (id=#{mail_queue_id}): #{update_ex.class}: #{update_ex.message}")
      end
    else
      logger.warn("DeliveryJob: mail_queue not found during rescue (id=#{mail_queue_id}) - cannot update status")
    end

    raise ex if status == :retrying
  end
end
