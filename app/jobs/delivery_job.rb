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
      # Avoid double execution if already processed/processing by another worker
      if %w[processing succeeded].include?(mail_queue.delivery_status)
        logger.info("DeliveryJob: Skipped mail_queue (id=#{mail_queue_id}) because status is already '#{mail_queue.delivery_status}'")
        return
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

    # Conditional update to prevent overwriting if modified by others
    result = MailQueue.where(id: mail_queue.id, delivery_status: :processing)
                      .update_all(delivery_status: :succeeded, locked_until: nil, updated_at: Time.current)

    if result.zero?
      logger.warn("DeliveryJob: Race condition detected on success. MailQueue(#{mail_queue.id}) was modified by others.")
    end
  rescue => ex
    status = Verbena::RetryableErrors.retryable_error?(ex) ? :retrying : :failed

    # Conditional update to safely set error status
    result = MailQueue.where(id: mail_queue_id, delivery_status: :processing)
                      .update_all(delivery_status: status, locked_until: nil, updated_at: Time.current)

    if result.zero?
      logger.warn("DeliveryJob: Race condition detected on error. MailQueue(#{mail_queue_id}) was modified by others. Skip status update.")
    end

    raise ex if status == :retrying
  end
end
