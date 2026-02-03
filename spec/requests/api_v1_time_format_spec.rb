require 'time'
require 'rails_helper'

RSpec.describe 'Api::V1 time format', type: :request do
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

  it 'returns ISO8601 UTC timestamps (ending with Z) in show response' do
    mq = FactoryBot.create(:mail_queue, timer_at: Time.current, token: token)

    get "/api/v1/mail_queues/#{mq.id}", headers: auth_headers
    expect(response).to have_http_status(:ok)
    body = json

    %w[timer_at created_at updated_at].each do |k|
      expect(body[k]).to be_a(String)
      expect(body[k]).to match(/Z\z/)
      # Parse to ensure valid ISO8601
      expect { Time.iso8601(body[k]) }.not_to raise_error
    end
  end

  it 'returns ISO8601 UTC (Z) for embedded responses when requested' do
    mq = FactoryBot.create(:mail_queue, token: token)
    FactoryBot.create(:delivery_response, mail_queue: mq, responded_at: Time.zone.parse('2025-01-02 03:04:05'))
    get "/api/v1/mail_queues/#{mq.id}", params: { include: 'responses' }, headers: auth_headers
    expect(response).to have_http_status(:ok)
    body = json
    expect(body['responses']).to be_a(Array)
    expect(body['responses'].first['responded_at']).to match(/Z$/)
    expect(body['responses'].first['created_at']).to match(/Z$/)
    expect(body['responses'].first['updated_at']).to match(/Z$/)
  end
end
