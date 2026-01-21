module Verbena
  module RetryableErrors
    RETRYABLE_ERRORS = [
      Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout,
      Net::SMTPServerBusy,
      Errno::ECONNRESET, Errno::ECONNREFUSED, Errno::ETIMEDOUT
    ].freeze

    def self.retryable_error?(exception)
      RETRYABLE_ERRORS.any? { |klass| exception.is_a?(klass) }
    end

    def self.retryable_errors
      RETRYABLE_ERRORS
    end
  end
end
