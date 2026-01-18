class DeliveryJob < ApplicationJob
  queue_as :default

  RETRYABLE_ERRORS = [
    Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout,
    Net::SMTPServerBusy,
    Errno::ECONNRESET, Errno::ECONNREFUSED, Errno::ETIMEDOUT
  ].freeze

  retry_on(*RETRYABLE_ERRORS, wait: :exponentially_longer, attempts: 5)

  def self.retryable_error?(exception)
    RETRYABLE_ERRORS.any? { |klass| exception.is_a?(klass) }
  end

  def perform(mail_queue_id)
    mail_queue = MailQueue.find_by(id: mail_queue_id)
    return unless mail_queue

    # Use the job_id as the job_id for logging/tracking purposes
    Verbena::DeliveryService.new(job_id: job_id).perform_one(mail_queue)
  end
end
