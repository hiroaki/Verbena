require 'rails_helper'

RSpec.describe 'Api::V1::MailQueues authorization', type: :request do
  let!(:token_a) do
    t = FactoryBot.build(:token, key: 'token_a_key')
    t.save!
    t
  end

  let!(:token_b) do
    t = FactoryBot.build(:token, key: 'token_b_key')
    t.save!
    t
  end

  let!(:mq_a) { FactoryBot.create(:mail_queue, token: token_a) }
  let!(:mq_b) { FactoryBot.create(:mail_queue, token: token_b) }

  let(:auth_headers_a) { { 'Authorization' => 'Token token="token_a_key"' } }
  let(:auth_headers_b) { { 'Authorization' => 'Token token="token_b_key"' } }

  def json
    JSON.parse(response.body)
  end

  it 'index returns only mail_queues owned by authenticated token' do
    get '/api/v1/mail_queues', headers: auth_headers_a
    expect(response).to have_http_status(:ok)
    ids = json.map { |h| h['id'] }
    expect(ids).to include(mq_a.id)
    expect(ids).not_to include(mq_b.id)
  end

  it 'show returns 404 for a mail_queue owned by another token' do
    get "/api/v1/mail_queues/#{mq_a.id}", headers: auth_headers_b
    expect(response).to have_http_status(:not_found)
  end

  it 'delete returns not found for a mail_queue owned by another token and does not delete it' do
    delete "/api/v1/mail_queues/#{mq_a.id}", headers: auth_headers_b
    expect(response).to have_http_status(:not_found)
    expect(MailQueue.exists?(mq_a.id)).to be_truthy
  end
end
