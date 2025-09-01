require 'rails_helper'

RSpec.describe 'Api::V1::MailQueues create validations', type: :request do
  let!(:token) do
    t = FactoryBot.build(:token, key: 'sekret')
    t.save!
    t
  end

  let(:auth_headers) do
    { 'Authorization' => 'Token token="sekret"' }
  end

  def json
    JSON.parse(response.body)
  end

  def post_eml(eml)
    post '/api/v1/mail_queues', params: { mail_queue: { eml: eml } }, headers: auth_headers
  end

  it 'returns 422 when EML exceeds VERBENA_EML_MAX_BYTES' do
    old = Verbena::Settings.config.eml_max_bytes
    Verbena::Settings.configure(eml_max_bytes: 10)
    begin
      post_eml('x' * 11)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json['code']).to eq('eml_too_large')
    ensure
      Verbena::Settings.configure(eml_max_bytes: old)
    end
  end

  it 'returns 422 when there are no recipients' do
    eml = <<~EML
      From: sender@example.com
      To:
      Subject: No recipients
      Date: Thu, 1 Jan 1970 00:00:00 +0000

      Body
    EML
    post_eml(eml)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(json['code']).to eq('no_recipients')
  end
end
