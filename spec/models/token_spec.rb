require 'rails_helper'

RSpec.describe Token, type: :model do
  describe 'コンストラクタ' do
    it 'インスタンス化できる' do
      expect(FactoryBot.build(:token).class).to eq described_class
    end
  end

  describe 'バリデーション' do
    before do
      @instance = FactoryBot.build(:token, params)
    end

    subject { @instance.valid? }

    describe 'label' do
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

    describe 'key' do
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
end
