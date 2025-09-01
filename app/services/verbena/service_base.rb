module Verbena
  class ServiceBase
    attr_accessor :logger
    attr_reader :settings

    def initialize(options = {})
      @logger = options[:logger] || Rails.logger
      @settings = options
    end
  end
end
