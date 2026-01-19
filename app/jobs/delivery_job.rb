class DeliveryJob < ApplicationJob
  queue_as :default

  DELIVERY_MAX_RETRIES = ENV.fetch("VERBENA_DELIVERY_MAX_RETRIES", 5).to_i
  retry_on(*Verbena::RetryableErrors.retryable_errors, wait: :exponentially_longer, attempts: DELIVERY_MAX_RETRIES)

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

    # Use the job_id as the job_id for logging/tracking purposes
    Verbena::DeliveryService.new(job_id: job_id).perform_one(mail_queue)
  end
end
