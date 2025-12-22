require 'rails_helper'
require 'rake'

RSpec.describe 'verbena:tokens rake tasks' do
  before do
    # Load the rake task
    # Ensure we don't reload if already loaded to avoid warnings or errors,
    # though rake_require usually handles this.
    Rake.application.rake_require 'tasks/verbena/tokens'
    Rake::Task.define_task(:environment)
  end

  describe 'verbena:tokens:revoke_expired' do
    let(:task) { Rake::Task['verbena:tokens:revoke_expired'] }

    before do
      task.reenable
    end

    # Integration test with real DB records
    context 'integration with TokenService' do
      let!(:expired_token) { FactoryBot.create(:token, key: 'expired', expires_at: 1.day.ago, revoked_at: nil) }
      let!(:active_token)  { FactoryBot.create(:token, key: 'active', expires_at: 1.day.from_now, revoked_at: nil) }

      context 'when invoked with dry argument' do
        it 'prints the count of tokens to be revoked but does not revoke them' do
          expect { task.invoke('dry') }.to output(/\[verbena:tokens:revoke_expired\] Dry run: 1 tokens would be revoked/).to_stdout

          expect(expired_token.reload.revoked_at).to be_nil
          expect(active_token.reload.revoked_at).to be_nil
        end
      end

      context 'when invoked without arguments' do
        it 'revokes expired tokens and prints the count' do
          expect { task.invoke }.to output(/\[verbena:tokens:revoke_expired\] Revoked 1 tokens/).to_stdout

          expect(expired_token.reload.revoked_at).not_to be_nil
          expect(active_token.reload.revoked_at).to be_nil
        end
      end
    end
  end
end
