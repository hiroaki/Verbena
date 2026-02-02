# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'mail'
require 'logger'
require 'openssl'

module Verbena
  # デモ用: HTTP 経由で Verbena API へ EML を送信する delivery_method
  # - 設定 `:return_response` が true の場合、HTTP 応答として `Net::HTTPResponse` を返します。
  # - 設定 `:return_response` が false (デフォルト) の場合、Action Mailer の慣習に従い元の `mail` オブジェクトを返します。
  # - HTTP レスポンスが 2xx 以外の場合は `DeliveryError` を発生させます。
  # - DNS/接続/タイムアウトなどの低レベルなネットワーク例外は、そのまま上位へ再送出されます（必要に応じて呼び出し側でラップしてください）。
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

      # logger は外部から与えられていればそれを使います（ない場合はインスタンスは遅延生成します）
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
        # ボディがある場合は追加情報として含める (例: エラー理由など)
        body = response.body.to_s
        error_message += ": #{body[0..200]}" unless body.empty?
        raise DeliveryError, error_message
      end

      response
    end
  end
end
