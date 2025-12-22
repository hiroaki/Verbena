require 'rails_helper'

RSpec.describe Token, type: :model do
  describe 'コンストラクタ' do
    it 'インスタンス化できる' do
      expect(FactoryBot.build(:token).class).to eq described_class
    end
  end

  describe 'バリデーション' do
    describe 'label' do
      subject { FactoryBot.build(:token, params).valid? }

      context do
        let!(:params) { { label: nil } }
        it { is_expected.to be false }
      end

      context do
        let!(:params) { { label: '' } }
        it { is_expected.to be false }
      end

      context do
        let!(:params) { { label: 'foo' } }
        it { is_expected.to be true }
      end
    end

    describe 'expires_at' do
      subject { FactoryBot.build(:token, params).valid? }

      context do
        let!(:params) { { expires_at: nil } }
        it { is_expected.to be false }
      end

      context do
        let!(:params) { { expires_at: 1.day.from_now } }
        it { is_expected.to be true }
      end
    end

    describe 'key' do
      describe '新規作成時' do
        subject { FactoryBot.build(:token, params).valid? }

        context do
          let!(:params) { { key: nil } }
          it { is_expected.to be false }
        end

        context do
          let!(:params) { { key: '' } }
          it { is_expected.to be false }
        end

        context do
          let!(:params) { { key: 'bar' } }
          it { is_expected.to be true }
        end

        context '同じ key で別の token が既に存在する場合' do
          let!(:existing_token) { FactoryBot.create(:token, key: 'duplicate-key') }
          let!(:params) { { key: 'duplicate-key' } }

          it 'create_unique! raises RecordInvalid with key error' do
            expect {
              Token.create_unique!(label: 'dup2', key: 'duplicate-key', expires_at: 1.day.from_now)
            }.to raise_error(ActiveRecord::RecordInvalid) do |e|
              expect(e.record.errors[:key]).to be_present
            end
          end
        end
      end

      describe '更新時' do
        let!(:token) { FactoryBot.create(:token, key: 'original-key') }

        context 'key を渡さずに label を更新する場合' do
          it 'バリデーションエラーが起きない' do
            token.label = 'updated-label'
            expect(token.valid?).to be true
          end
        end

        context 'key を渡さずに保存する場合' do
          it 'key_digest_hash が変わらない' do
            original_digest = token.key_digest_hash
            token.label = 'updated-label'
            token.save!
            expect(token.key_digest_hash).to eq(original_digest)
          end
        end

        context 'key を更新しようとした場合' do
          it 'バリデーションエラーになる' do
            token.key = 'new-key'
            expect(token.valid?).to be false
            expect(token.errors[:key]).to be_present
          end
        end
      end
    end
  end

  describe 'クラスメソッド' do
    describe '.authenticated?' do
      subject { described_class.authenticated?(key) }

      context do
        before do
          FactoryBot.create(:token, key: 'apple pine')
        end

        context do
          let!(:key) { 'apple pine' }
          it { is_expected.to be true }
        end

        context do
          let!(:key) { 'banana' }
          it { is_expected.to be false }
        end

        context do
          let!(:key) { nil }
          it { is_expected.to be false }
        end

        context do
          let!(:key) { '' }
          it { is_expected.to be false }
        end
      end

      context 'with expiry and revocation' do
        let!(:key) { test_key }
        let!(:test_key) { 'exp-key' }

        context 'valid (not expired, not revoked)' do
          let!(:tok) { FactoryBot.create(:token, key: test_key, expires_at: 1.day.from_now, revoked_at: nil, last_used_at: nil) }
          it 'returns true and updates last_used_at' do
            expect(subject).to be true
            expect(tok.reload.last_used_at).to be_within(5.seconds).of(Time.current)
          end
        end

        context 'expired' do
          let!(:tok) { FactoryBot.create(:token, key: test_key, expires_at: 1.day.ago, revoked_at: nil) }
          it { is_expected.to be false }
        end

        context 'revoked' do
          let!(:tok) { FactoryBot.create(:token, key: test_key, expires_at: 1.day.from_now, revoked_at: Time.current) }
          it { is_expected.to be false }
        end
      end

      context 'when last_used_at update fails' do
        let!(:key) { 'log-key' }
        it 'returns true and logs a warning' do
          tok = FactoryBot.create(:token, key: key, expires_at: 1.day.from_now, revoked_at: nil, last_used_at: nil)
          allow_any_instance_of(Token).to receive(:update_columns).and_raise(StandardError.new('boom'))
          expect(Rails.logger).to receive(:warn).with(a_string_matching(/\[Token\] last_used_at update failed id=#{tok.id} error_class=StandardError error=boom/))
          expect(described_class.authenticated?(key)).to be true
        end
      end
    end
  end

  describe '#active?' do
    context 'when not revoked and not expired' do
      let!(:tok) { FactoryBot.create(:token, key: 'ok', expires_at: 1.day.from_now, revoked_at: nil) }
      it 'returns true' do
        expect(tok.active?).to be true
      end
    end

    context 'when revoked' do
      let!(:tok) { FactoryBot.create(:token, key: 'revoked', expires_at: 1.day.from_now, revoked_at: Time.current) }
      it 'returns false' do
        expect(tok.active?).to be false
      end
    end

    context 'when expired' do
      let!(:tok) { FactoryBot.create(:token, key: 'expired', expires_at: 1.day.ago, revoked_at: nil) }
      it 'returns false' do
        expect(tok.active?).to be false
      end
    end
  end

  describe 'scopes' do
    let!(:active_tok) { FactoryBot.create(:token, key: 'scope-active', expires_at: 1.day.from_now, revoked_at: nil) }
    let!(:expired_tok) { FactoryBot.create(:token, key: 'scope-expired', expires_at: 1.day.ago, revoked_at: nil) }
    let!(:revoked_tok) { FactoryBot.create(:token, key: 'scope-revoked', expires_at: 1.day.from_now, revoked_at: Time.current) }

    it 'returns only active tokens for .active' do
      expect(Token.active).to include(active_tok)
      expect(Token.active).not_to include(expired_tok, revoked_tok)
    end

    it 'returns only expired (but not revoked) tokens for .expired' do
      expect(Token.expired).to include(expired_tok)
      expect(Token.expired).not_to include(active_tok, revoked_tok)
    end
  end

  describe '#revoke!' do
    it 'sets revoked_at to now when called without args' do
      tok = FactoryBot.create(:token, key: 'rev1', expires_at: 1.day.from_now, revoked_at: nil)
      tok.revoke!
      expect(tok.reload.revoked_at).not_to be_nil
    end

    it 'sets revoked_at to the provided time' do
      t = 2.days.ago
      tok = FactoryBot.create(:token, key: 'rev2', expires_at: 1.day.from_now, revoked_at: nil)
      tok.revoke!(t)
      expect(tok.reload.revoked_at.to_i).to eq t.to_i
    end

    it 'updates revoked_at if already revoked' do
      t0 = 3.days.ago
      tok = FactoryBot.create(:token, key: 'rev3', expires_at: 1.day.from_now, revoked_at: t0)
      new_t = Time.current
      tok.revoke!(new_t)
      expect(tok.reload.revoked_at.to_i).to eq new_t.to_i
    end
  end
end
