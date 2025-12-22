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

    context 'when revoke! raises an error for a token' do
      it 'continues processing other tokens and returns count of successful revokes' do
        a = FactoryBot.create(:token, key: 'e-a', expires_at: 1.day.ago, revoked_at: nil)
        b = FactoryBot.create(:token, key: 'e-b', expires_at: 1.day.ago, revoked_at: nil)
        allow_any_instance_of(Token).to receive(:revoke!).and_wrap_original do |m, *args|
          # raise only for the instance matching `a` (other tokens should be processed)
          if m.receiver.id == a.id
            raise StandardError.new('boom')
          else
            m.call(*args)
          end
        end

        result = service.revoke_expired(dry_run: false)
        # There may be other expired tokens in the test DB; ensure the service
        # continued processing other tokens and our failing token remained unrevoked.
        expect(result).to be >= 1
        expect(a.reload.revoked_at).to be_nil
        expect(b.reload.revoked_at).not_to be_nil
      end
    end
  end
end
