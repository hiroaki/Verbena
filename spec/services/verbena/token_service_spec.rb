require 'rails_helper'

RSpec.describe Verbena::TokenService, type: :service do
  let(:logger) { Logger.new(IO::NULL) }
  let(:service) { described_class.new(logger: logger) }

  describe '#revoke_expired' do
    let!(:expired_token) { FactoryBot.create(:token, key: 'expired', expires_at: 1.day.ago, revoked_at: nil) }
    let!(:active_token)  { FactoryBot.create(:token, key: 'active',  expires_at: 1.day.from_now, revoked_at: nil) }

    context 'dry run' do
      it 'returns count and does not revoke' do
        expect(service.revoke_expired(dry_run: true)).to eq(1)
        expect(expired_token.reload.revoked_at).to be_nil
        expect(active_token.reload.revoked_at).to be_nil
      end
    end

    context 'execute' do
      it 'revokes only expired tokens and returns count' do
        expect(service.revoke_expired(dry_run: false)).to eq(1)
        expect(expired_token.reload.revoked_at).not_to be_nil
        expect(active_token.reload.revoked_at).to be_nil
      end
    end
  end
end
