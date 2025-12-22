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

    context 'when expired tokens are already revoked' do
      let!(:expired_revoked) { FactoryBot.create(:token, key: 'expired_revoked', expires_at: 2.days.ago, revoked_at: 1.day.ago) }

      it 'does not count or revoke already-revoked tokens' do
        # dry run should still only count the non-revoked expired token
        expect(service.revoke_expired(dry_run: true)).to eq(1)

        # execute should revoke only the non-revoked expired token
        result = service.revoke_expired(dry_run: false)
        expect(result).to eq(1)

        # ensure the already-revoked token remains revoked and untouched
        expect(expired_revoked.reload.revoked_at).not_to be_nil
      end
    end

    context 'when revoke! raises an error for a token' do
      it 'continues processing other tokens and returns count of successful revokes' do
        token_error = FactoryBot.create(:token, key: 'e-a', expires_at: 1.day.ago, revoked_at: nil)
        token_success = FactoryBot.create(:token, key: 'e-b', expires_at: 1.day.ago, revoked_at: nil)

        # raise only for `token_error`; allow others (including `token_success`) to call the real method
        allow(token_error).to receive(:revoke!).and_raise(StandardError.new('boom'))
        allow(token_success).to receive(:revoke!).and_call_original

        # Use a relation stub so the batch includes the same instances
        relation = Token.expired
        allow(Token).to receive(:expired).and_return(relation)
        allow(relation).to receive(:find_in_batches).and_yield([token_error, token_success, expired_token])

        initial_expired_count = relation.count
        result = service.revoke_expired(dry_run: false)

        # The service should return the number of tokens it actually revoked.
        actual_revoked_count = [token_error, token_success, expired_token].count { |t| t.reload.revoked_at.present? }
        expect(result).to eq(actual_revoked_count)

        # token_error should have failed to be revoked; token_success should be revoked
        expect(token_error.reload.revoked_at).to be_nil
        expect(token_success.reload.revoked_at).not_to be_nil
      end
    end
  end
end
