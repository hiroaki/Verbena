# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'mail'
require 'logger'

module Verbena
  # デモ用: HTTP 経由で Verbena API へ EML を送信する delivery_method
  class HttpDelivery
    attr_accessor :settings

    def initialize(values)
      defaults = {
        logger: (defined?(Rails) && Rails.respond_to?(:logger) ? Rails.logger : Logger.new($stdout)),
        return_response: false,
        open_timeout: 5,
        read_timeout: 30,
        verify_ssl: true, # デフォルトはSSL検証あり
      }
      merged = defaults.merge(values || {})
      @settings = merged.respond_to?(:transform_keys) ? merged.transform_keys { |k| k.to_sym rescue k } : merged
    end

    def deliver!(mail)
      ensure_required_settings!
      mail[:bcc].include_in_headers = true if mail[:bcc]

      response = post_eml!(mail.to_s)
      settings[:logger].info(log_message("delivered response=#{response.code}", mail))

      settings[:return_response] ? response : mail
    rescue => ex
      settings[:logger].error(log_message("error #{ex.class}: #{ex.message}", mail))
      raise
    end

    private

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
        # verify_ssl フラグで制御 (デフォルト: true -> VERIFY_PEER)
        # false が渡された場合のみ VERIFY_NONE とする
        http.verify_mode = settings[:verify_ssl] ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE
      end
      http.open_timeout = settings[:open_timeout] if settings[:open_timeout]
      http.read_timeout = settings[:read_timeout] if settings[:read_timeout]

      response = http.request(req)
      raise "unexpected response #{response.code}" unless response.code.to_s.start_with?('2')

      response
    end

    def log_message(reason, mail)
      destinations = mail.respond_to?(:destinations) ? Array(mail.destinations) : []
      "Verbena::HttpDelivery#deliver! #{reason} destinations=[#{destinations.join(', ')}]"
    end
  end
end
