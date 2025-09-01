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
  end
end
