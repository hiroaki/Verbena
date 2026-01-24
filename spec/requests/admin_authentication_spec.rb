require 'rails_helper'

RSpec.describe 'Admin Basic Authentication', type: :request do
  def basic_auth_header(user, pass)
    { 'Authorization' => ActionController::HttpAuthentication::Basic.encode_credentials(user, pass) }
  end

  before do
    Verbena::Settings.reset!
    # mission_control-jobs calls server.activating which expects certain queue adapter
    # behavior; stub out activating to avoid adapter-specific calls in tests.
    allow_any_instance_of(MissionControl::Jobs::Server).to receive(:activating).and_return(nil)
  end

  it 'allows access with correct credentials' do
    Verbena::Settings.configure(admin_username: 'admin', admin_password: 'jobs')
    get '/admin/jobs', headers: basic_auth_header('admin', 'jobs')
    expect(response).to have_http_status(:ok)
  end

  it 'rejects with wrong username' do
    Verbena::Settings.configure(admin_username: 'admin', admin_password: 'jobs')
    get '/admin/jobs', headers: basic_auth_header('bad', 'jobs')
    expect(response).to have_http_status(:unauthorized)
    expect(response.headers['WWW-Authenticate']).to be_present
  end

  it 'rejects with wrong password' do
    Verbena::Settings.configure(admin_username: 'admin', admin_password: 'jobs')
    get '/admin/jobs', headers: basic_auth_header('admin', 'wrong')
    expect(response).to have_http_status(:unauthorized)
    expect(response.headers['WWW-Authenticate']).to be_present
  end

  it 'rejects when credentials are not configured' do
    # Ensure readers return nil/blank
    Verbena::Settings.configure(admin_username: nil, admin_password: nil)
    get '/admin/jobs', headers: basic_auth_header('admin', 'jobs')
    expect(response).to have_http_status(:unauthorized)
  end

  it 'rejects when no Authorization header is provided' do
    Verbena::Settings.configure(admin_username: 'admin', admin_password: 'jobs')
    get '/admin/jobs'
    expect(response).to have_http_status(:unauthorized)
    expect(response.headers['WWW-Authenticate']).to be_present
  end
end
