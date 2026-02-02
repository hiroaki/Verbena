# frozen_string_literal: true

require 'rails_helper'
require 'net/http'
require_relative '../../../lib/verbena/http_delivery'

RSpec.describe Verbena::HttpDelivery do
  let(:url) { 'http://example.test/api/v1/mail_queues' }
  let(:token) { 'secret-token' }
  let(:settings) { { url_enqueue: url, access_token: token, return_response: true, logger: Logger.new(IO::NULL), verify_ssl: false } }
  let(:delivery) { described_class.new(settings) }
  let(:mail) { Mail.new(to: 'to@example.test', from: 'from@example.test', subject: 'hi', body: 'hello') }

  before do
    # ensure Mail is available
    expect(Mail).to be
  end

  it 'returns Net::HTTPResponse on success when return_response is true' do
    response = instance_double(Net::HTTPResponse, code: '200', body: '', to_s: 'resp')

    http_double = double('http', request: response)
    allow(http_double).to receive(:use_ssl=)
    allow(http_double).to receive(:verify_mode=)
    allow(http_double).to receive(:open_timeout=)
    allow(http_double).to receive(:read_timeout=)
    allow(Net::HTTP).to receive(:new).and_return(http_double)

    expect(delivery.deliver!(mail)).to be(response)
  end

  it 'raises DeliveryError on non-2xx responses' do
    # Use a plain String for the response body to better mirror Net::HTTPResponse
    response = double('response', code: '500', body: 'server error')

    http_double = double('http', request: response)
    allow(http_double).to receive(:use_ssl=)
    allow(http_double).to receive(:verify_mode=)
    allow(http_double).to receive(:open_timeout=)
    allow(http_double).to receive(:read_timeout=)
    allow(Net::HTTP).to receive(:new).and_return(http_double)

    expect { delivery.deliver!(mail) }.to raise_error(Verbena::HttpDelivery::DeliveryError)
  end

  it 'returns mail object when return_response is false' do
    settings2 = settings.merge(return_response: false)
    d2 = described_class.new(settings2)

    response = double('response', code: '200', body: double('body', to_s: '', present?: false))
    http_double = double('http', request: response)
    allow(http_double).to receive(:use_ssl=)
    allow(http_double).to receive(:verify_mode=)
    allow(http_double).to receive(:open_timeout=)
    allow(http_double).to receive(:read_timeout=)
    allow(Net::HTTP).to receive(:new).and_return(http_double)

    result = d2.deliver!(mail)
    expect(result).to be(mail)
  end
end
