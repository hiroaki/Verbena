# frozen_string_literal: true

require 'minitest/autorun'
require 'ostruct'
require 'net/http'
require 'openssl'

# Avoid requiring the mail gem so this test can run standalone.
module Kernel
  alias_method :__verbena_require, :require

  def require(name)
    return false if name == 'mail'

    __verbena_require(name)
  end
end

original = ENV['VERBENA_ENABLE']
ENV['VERBENA_ENABLE'] = 'false'
require_relative 'verbena_injector'
ENV['VERBENA_ENABLE'] = original

module Kernel
  alias_method :require, :__verbena_require
end

class VerbenaHttpDeliveryPostEmlTest < Minitest::Test
  class HttpStub
    def initialize(test, response)
      @test = test
      @response = response
      @calls = {}
    end

    def use_ssl=(value)
      @calls[:use_ssl] = value
    end

    def verify_mode=(value)
      @calls[:verify_mode] = value
    end

    def open_timeout=(value)
      @calls[:open_timeout] = value
    end

    def read_timeout=(value)
      @calls[:read_timeout] = value
    end

    def request(req)
      @calls[:request] = req
      @response
    end

    def verify
      @test.assert_equal true, @calls[:use_ssl]
      @test.assert_equal OpenSSL::SSL::VERIFY_NONE, @calls[:verify_mode]
      @test.assert_equal 1, @calls[:open_timeout]
      @test.assert_equal 1, @calls[:read_timeout]
      @test.assert_instance_of Net::HTTP::Post, @calls[:request]
      @test.assert_equal 'Token token="token"', @calls[:request]['Authorization']
    end
  end
  def setup
    @settings = {
      url_enqueue: 'https://example.com/api/mail',
      access_token: 'token',
      verify_ssl: false,
      open_timeout: 1,
      read_timeout: 1
    }
    @delivery = Verbena::HttpDelivery.new(@settings)
    @delivery.instance_variable_set(:@logger, Logger.new(IO::NULL))
  end

  def test_post_eml_success_returns_response
    fake_response = OpenStruct.new(code: '200', body: 'OK')
    http = build_http_mock(fake_response)

    with_http_stub(http) do
      result = @delivery.send(:post_eml!, 'eml data')
      assert_equal fake_response, result
    end

    http.verify
  end

  def test_post_eml_failure_raises_delivery_error
    fake_response = OpenStruct.new(code: '500', body: 'Oops')
    http = build_http_mock(fake_response)

    with_http_stub(http) do
      error = assert_raises(Verbena::HttpDelivery::DeliveryError) do
        @delivery.send(:post_eml!, 'eml data')
      end
      assert_includes error.message, 'status 500'
      assert_includes error.message, 'Oops'
    end

    http.verify
  end

  private

  def build_http_mock(response)
    HttpStub.new(self, response)
  end

  def with_http_stub(http)
    singleton = class << Net::HTTP; self; end
    original = Net::HTTP.method(:new)
    singleton.define_method(:new) { |_host, _port| http }
    yield
  ensure
    singleton.define_method(:new) { |*args| original.call(*args) }
  end
end

class VerbenaHttpDeliveryDeliverTest < Minitest::Test
  class FakeBcc
    attr_accessor :include_in_headers
  end

  class FakeMail
    def initialize(bcc: true, destinations: ['user@example.com'], eml: 'EML')
      @bcc = bcc ? FakeBcc.new : nil
      @destinations = destinations
      @eml = eml
    end

    def [](key)
      return @bcc if key == :bcc

      nil
    end

    def destinations
      @destinations
    end

    def to_s
      @eml
    end

    def bcc
      @bcc
    end
  end

  def setup
    @settings = {
      url_enqueue: 'https://example.com/api/mail',
      access_token: 'token',
      verify_ssl: false,
      open_timeout: 1,
      read_timeout: 1,
      return_response: false
    }
    @delivery = Verbena::HttpDelivery.new(@settings)
    @delivery.instance_variable_set(:@logger, Logger.new(IO::NULL))
  end

  def test_deliver_returns_mail_by_default
    mail = FakeMail.new
    response = OpenStruct.new(code: '200')

    @delivery.define_singleton_method(:post_eml!) { |_eml| response }

    result = @delivery.deliver!(mail)
    assert_equal mail, result
  end

  def test_deliver_returns_response_when_configured
    mail = FakeMail.new
    response = OpenStruct.new(code: '200')

    @delivery.settings[:return_response] = true
    @delivery.define_singleton_method(:post_eml!) { |_eml| response }

    result = @delivery.deliver!(mail)
    assert_equal response, result
  end

  def test_deliver_sets_bcc_include_in_headers
    mail = FakeMail.new(bcc: true)
    response = OpenStruct.new(code: '200')

    @delivery.define_singleton_method(:post_eml!) { |_eml| response }

    @delivery.deliver!(mail)
    assert_equal true, mail.bcc.include_in_headers
  end

  def test_deliver_posts_mail_string
    eml = <<~EML
      From: sender@example.com
      To: user@example.com
      Bcc: secret@example.com
      Subject: test

      body
    EML
    mail = FakeMail.new(eml: eml)
    response = OpenStruct.new(code: '200')
    captured = nil

    @delivery.define_singleton_method(:post_eml!) do |eml_string|
      captured = eml_string
      response
    end

    @delivery.deliver!(mail)
    assert_equal eml, captured
    # Ensure Bcc header is not stripped from EML
    assert_match(/^Bcc: secret@example.com$/m, captured)
  end
end
