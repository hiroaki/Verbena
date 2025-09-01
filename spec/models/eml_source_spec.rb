require 'rails_helper'

RSpec.describe EmlSource, type: :model do
  describe 'コンストラクタ' do
    it 'インスタンス化できる' do
      expect(FactoryBot.build(:eml_source).class).to eq described_class
    end
  end

  describe 'バリデーション' do
    before do
      @instance = FactoryBot.build(:eml_source, params)
    end

    subject { @instance.valid? }

    describe 'eml' do
      context do
        let!(:params) { { eml: nil } }
        it { is_expected.to be false }
      end

      context do
        let!(:params) { { eml: '' } }
        it { is_expected.to be false }
      end

      context do
        let!(:params) { { eml: 'From: me' } }
        it { is_expected.to be true }
      end
    end
  end
end
