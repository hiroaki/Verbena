require 'rails_helper'

RSpec.describe 'API token authentication', type: :request do
  def auth_headers(token)
    { 'Authorization' => %Q(Token token="#{token}") }
  end

  describe 'GET /api/v1/mail_queues requires valid token' do
    it 'returns 200 with a valid (not expired, not revoked) token' do
      FactoryBot.create(:token, key: 'ok-token', expires_at: 1.day.from_now, revoked_at: nil)
      get '/api/v1/mail_queues', headers: auth_headers('ok-token')
      expect(response).to have_http_status(:ok)
    end

    it 'returns 401 with an expired token' do
      FactoryBot.create(:token, key: 'expired-token', expires_at: 1.day.ago, revoked_at: nil)
      get '/api/v1/mail_queues', headers: auth_headers('expired-token')
      expect(response).to have_http_status(:unauthorized)
      json = JSON.parse(response.body)
      expect(json['code']).to eq('unauthorized')
    end

    it 'returns 401 with a revoked token' do
      FactoryBot.create(:token, key: 'revoked-token', expires_at: 1.day.from_now, revoked_at: Time.current)
      get '/api/v1/mail_queues', headers: auth_headers('revoked-token')
      expect(response).to have_http_status(:unauthorized)
      json = JSON.parse(response.body)
      expect(json['code']).to eq('unauthorized')
    end

    it 'associates created mail queues with the authenticated token and isolates tokens' do
      # token A and token B
      FactoryBot.create(:token, key: 'token-a', expires_at: 1.day.from_now, revoked_at: nil)
      FactoryBot.create(:token, key: 'token-b', expires_at: 1.day.from_now, revoked_at: nil)

      eml = <<~EML
        From: sender@example.com
        To: recipient@example.com
        Subject: Hello
        Date: Thu, 1 Jan 1970 00:00:00 +0000

        Body
      EML

      # Create a mail queue as token-b
      post '/api/v1/mail_queues', params: { mail_queue: { eml: eml } }, headers: auth_headers('token-b')
      expect(response).to have_http_status(:ok)
      created = JSON.parse(response.body)
      expect(created['message']).to eq('ok')
      created_id = created['ids'].first

      # token-b should see the created mail queue
      get '/api/v1/mail_queues', headers: auth_headers('token-b')
      expect(response).to have_http_status(:ok)
      ids_b = JSON.parse(response.body).map { |h| h['id'] }
      expect(ids_b).to include(created_id)

      # token-a must NOT see token-b's mail queue even immediately after creation
      get '/api/v1/mail_queues', headers: auth_headers('token-a')
      expect(response).to have_http_status(:ok)
      ids_a = JSON.parse(response.body).map { |h| h['id'] }
      expect(ids_a).not_to include(created_id)
    end
  end
end
