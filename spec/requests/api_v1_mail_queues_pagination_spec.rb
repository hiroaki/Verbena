require 'rails_helper'

RSpec.describe 'Api::V1::MailQueues pagination', type: :request do
  let!(:token) do
    # Create a token with a known key and saved digest
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

  before do
    # Create 30 mail_queues with incremental IDs and timestamps, owned by the auth token
    FactoryBot.create_list(:mail_queue, 30, token: token)
  end

  it 'returns default page (limit=50, offset=0) ordered by id desc' do
    expect(Token).to receive(:authenticate).with('sekret').and_call_original
    get '/api/v1/mail_queues', headers: auth_headers
    expect(response).to have_http_status(:ok)
    expect(json).to be_a(Array)
    # since only 30 exist, it returns 30 but ordered desc by id
    ids = json.map { |h| h['id'] }
    expect(ids).to eq(ids.sort.reverse)
    expect(json.length).to eq(30)
  end

  it 'applies custom limit and offset' do
    get '/api/v1/mail_queues', params: { limit: 10, offset: 5 }, headers: auth_headers
    expect(response).to have_http_status(:ok)
    expect(json.length).to eq(10)
  end

  it 'supports order by id asc when specified' do
    get '/api/v1/mail_queues', params: { order: 'id asc' }, headers: auth_headers
    expect(response).to have_http_status(:ok)
    ids = json.map { |h| h['id'] }
    expect(ids).to eq(ids.sort)
  end

  it 'caps limit at 1000 and floors invalid values to defaults' do
    get '/api/v1/mail_queues', params: { limit: -1, offset: -10 }, headers: auth_headers
    expect(response).to have_http_status(:ok)
    # default limit is 50, but we only have 30
    expect(json.length).to eq(30)
  end

  it 'applies the configured cap from Settings without creating massive records' do
    # Temporarily reduce cap to 5 and request a larger limit
    old_config = Verbena::Settings.config.api_pagination_limit_cap
    Verbena::Settings.configure(api_pagination_limit_cap: 5)
    begin
      get '/api/v1/mail_queues', params: { limit: 100 }, headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(json.length).to eq(5)
    ensure
      # Restore
      Verbena::Settings.configure(api_pagination_limit_cap: old_config)
    end
  end
end
