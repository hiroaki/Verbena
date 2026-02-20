# frozen_string_literal: true

# ==============================================================================
# Verbena Injector
#
# This file is a standalone initializer script for using Verbena (Mail Delivery System).
#
# Usage:
# 1. Place this file in the `config/initializers/` directory of your Rails application.
# 2. Set the following environment variables and restart your application.
#
#    VERBENA_ENABLE=true             # Enable Verbena injector (required)
#    VERBENA_URL=https://...         # Verbena API endpoint
#    VERBENA_TOKEN=...               # API access token
#    VERBENA_RETURN_RESPONSE=false   # (optional) true returns Net::HTTPResponse
#    VERBENA_VERIFY_SSL=true         # (optional) SSL certificate verification
#    VERBENA_OPEN_TIMEOUT=5          # (optional) HTTP open timeout (seconds)
#    VERBENA_READ_TIMEOUT=30         # (optional) HTTP read timeout (seconds)
# ==============================================================================

require 'net/http'
require 'uri'
require 'mail'
require 'logger'
require 'openssl'

# Verbena::HttpDelivery class definition (inlined)
module Verbena
  class HttpDelivery
    class DeliveryError < StandardError; end

    DEFAULTS = {
      logger: nil,
      return_response: false,
      open_timeout: 5,
      read_timeout: 30,
      verify_ssl: true,
    }.freeze

    attr_accessor :settings

    def initialize(values)
      merged = DEFAULTS.merge(values || {})
      @settings = if merged.respond_to?(:transform_keys)
                    merged.transform_keys { |k| k.is_a?(String) ? k.to_sym : k }
                  else
                    merged
                  end

      @logger = @settings.delete(:logger)
    end

    def deliver!(mail)
      ensure_required_settings!
      mail[:bcc].include_in_headers = true if mail[:bcc]

      response = post_eml!(mail.to_s)
      logger.info(log_message("delivered response=#{response.code}", mail))

      settings[:return_response] ? response : mail
    rescue => ex
      logger.error(log_message("error #{ex.class}: #{ex.message}", mail))
      raise
    end

    private

    def logger
      @logger ||= Logger.new($stdout)
    end

    def log_message(reason, mail)
      destinations = mail.respond_to?(:destinations) ? Array(mail.destinations) : []
      "Verbena::HttpDelivery#deliver! #{reason} destinations=[#{destinations.join(', ')}]"
    end

    def ensure_required_settings!
      raise ArgumentError, 'url_enqueue is required' if settings[:url_enqueue].to_s.strip.empty?
      raise ArgumentError, 'access_token is required' if settings[:access_token].to_s.strip.empty?
    end

    def post_eml!(eml_string)
      uri = URI.parse(settings[:url_enqueue].to_s)

      req = Net::HTTP::Post.new(uri.request_uri)
      req['Authorization'] = %(Token token="#{settings[:access_token]}")
      req.set_form([['mail_queue[eml]', eml_string]], 'multipart/form-data')

      http = Net::HTTP.new(uri.host, uri.port)
      if uri.scheme == 'https'
        http.use_ssl = true
        http.verify_mode = settings[:verify_ssl] ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE
      end
      http.open_timeout = settings[:open_timeout] if settings[:open_timeout]
      http.read_timeout = settings[:read_timeout] if settings[:read_timeout]

      response = http.request(req)
      unless response.code.to_s.start_with?('2')
        error_message = "API request failed with status #{response.code}"
        body = response.body.to_s
        error_message += ": #{body[0..200]}" unless body.empty?
        raise DeliveryError, error_message
      end

      response
    end
  end
end

# ActionMailer injection setup
if ENV['VERBENA_ENABLE'] == 'true'
  # Use to_prepare block for Rails reload support
  Rails.application.reloader.to_prepare do
    Rails.logger.info '[Verbena] Injecting custom delivery method...'

    # Validate required environment variables early so failures occur at boot
    # Strip surrounding whitespace to avoid accidental errors from padded values
    url = ENV['VERBENA_URL'].to_s.strip
    token = ENV['VERBENA_TOKEN'].to_s.strip
    if url.strip.empty? || token.strip.empty?
      message = '[Verbena] VERBENA_URL and VERBENA_TOKEN must be set when VERBENA_ENABLE=true'
      Rails.logger.error(message)
      raise ArgumentError, message
    end

    settings = {
      url_enqueue:     url,
      access_token:    token,
      return_response: ENV['VERBENA_RETURN_RESPONSE'] == 'true',
      verify_ssl:      ENV.fetch('VERBENA_VERIFY_SSL', 'true') == 'true',
      open_timeout:    (ENV['VERBENA_OPEN_TIMEOUT'] || 5).to_i,
      read_timeout:    (ENV['VERBENA_READ_TIMEOUT'] || 30).to_i
    }

    # Register custom delivery_method as :verbena
    ActionMailer::Base.add_delivery_method :verbena, Verbena::HttpDelivery, settings

    # Override default delivery_method to :verbena
    ActionMailer::Base.delivery_method = :verbena

    Rails.logger.info "[Verbena] ActionMailer is now configured to use :verbena adapter (URL: #{settings[:url_enqueue]})"
  end
end
