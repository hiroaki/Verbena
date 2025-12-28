module Verbena
  class ServiceBase
    attr_accessor :logger
    attr_reader :settings

    def initialize(options = {})
      @logger = options[:logger] || Rails.logger
      @settings = options
    end

    # Always returns a Hash for structured (JSON) logging
    def structured_log_hash(**args)
      {
        'event' => args[:event],
        'level' => args[:level],
        'session_id' => args[:session_id],
        'mail_queue_id' => args[:mail_queue_id],
        'message_id' => args[:message_id],
        'smtp_status' => args[:smtp_status],
        'error' => args[:error],
        'message' => args[:message]
      }.compact
    end

    # Always returns a human-friendly String for legacy (line) logging
    def structured_log_line(**args)
      structured_log_hash(**args).map { |k, v| "#{k}=#{v}" }.join(' | ')
    end

    # Wrapper: auto-selects hash or line based on json_logging_enabled?
    def structured_log(**args)
      if json_logging_enabled?
        structured_log_hash(**args)
      else
        structured_log_line(**args)
      end
    end

    def json_logging_enabled?
      # Detect by checking formatter class
      Rails.logger.formatter.is_a?(::Verbena::JsonLogFormatter) rescue false
    end

    # Coerce various input values to boolean using Rails casting rules.
    # Useful for web params and rake args ("1", "true", "t", "yes", etc.).
    def self.truthy?(val)
      @boolean_type ||= ActiveModel::Type::Boolean.new
      !!@boolean_type.cast(val)
    end

    # Instance-level convenience delegating to the class method
    def truthy?(val)
      self.class.truthy?(val)
    end
  end
end
