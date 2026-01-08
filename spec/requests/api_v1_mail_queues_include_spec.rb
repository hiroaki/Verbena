require 'rails_helper'

RSpec.describe 'Api::V1::MailQueues include responses', type: :request do
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

  it 'returns latest response when include=responses:latest' do
    mq = FactoryBot.create(:mail_queue)
    # older
    FactoryBot.create(:delivery_response, mail_queue: mq, responded_at: 1.day.ago, status: '250', message_id: 'm-old')
    # latest
    latest = FactoryBot.create(:delivery_response, mail_queue: mq, responded_at: Time.current, status: '250', message_id: 'm-new')

    get "/api/v1/mail_queues/#{mq.id}", params: { include: 'responses:latest' }, headers: auth_headers
    expect(response).to have_http_status(:ok)
    expect(json['id']).to eq(mq.id)
    expect(json['responses']).to be_a(Array)
    expect(json['responses'].length).to eq(1)
    expect(json['responses'][0]['message_id']).to eq('m-new')
  end

  it 'returns all responses when include=responses' do
    mq = FactoryBot.create(:mail_queue)
    FactoryBot.create_list(:delivery_response, 3, mail_queue: mq)

    get "/api/v1/mail_queues/#{mq.id}", params: { include: 'responses' }, headers: auth_headers
    expect(response).to have_http_status(:ok)
    expect(json['responses']).to be_a(Array)
    expect(json['responses'].length).to eq(3)
  end

  it 'applies default limit when responses exceed cap' do
    mq = FactoryBot.create(:mail_queue)
    FactoryBot.create_list(:delivery_response, 60, mail_queue: mq)

    get "/api/v1/mail_queues/#{mq.id}", params: { include: 'responses' }, headers: auth_headers
    expect(response).to have_http_status(:ok)
    expect(json['responses']).to be_a(Array)
    expect(json['responses'].length).to eq(50)
  end

  it 'honors responses_limit param up to the maximum' do
    mq = FactoryBot.create(:mail_queue)
    FactoryBot.create_list(:delivery_response, 120, mail_queue: mq)

    get "/api/v1/mail_queues/#{mq.id}", params: { include: 'responses', responses_limit: 200 }, headers: auth_headers
    expect(response).to have_http_status(:ok)
    expect(json['responses']).to be_a(Array)
    expect(json['responses'].length).to eq(100)
  end

  it 'returns unified error shape for not found' do
    get "/api/v1/mail_queues/999999", headers: auth_headers
    expect(response.status).to eq(404)
    body = json
    expect(body['code']).to eq('not_found')
    expect(body['message']).to be_a(String)
  end
end
