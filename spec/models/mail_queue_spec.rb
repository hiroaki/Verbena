require 'rails_helper'

RSpec.describe MailQueue, type: :model do
  let!(:genzai_jikoku) { Time.zone.parse('2023-10-23 10:11:22') }

  describe 'コンストラクタ' do
    describe 'インスタンスのクラスについて' do
      it { expect(described_class.new).to be_a(described_class) }
    end

    describe '初期値について' do
      before do
        travel_to genzai_jikoku
        @instance = described_class.new(params)
      end

      context 'コンストラクタに値を指定しない場合' do
        let!(:params) { {} }
        it 'timer_at に現在時刻がセットされる' do
          expect(@instance.timer_at).to eq genzai_jikoku
        end
      end

      context 'コンストラクタに timer_at の値を指定する場合' do
        let!(:params) { { timer_at: genzai_jikoku + 1.hour } }
        it 'timer_at に指定の値がセットされる' do
          expect(@instance.timer_at).to eq genzai_jikoku + 1.hour
        end
      end
    end
  end

  describe 'バリデーション' do
    before do
      @instance = FactoryBot.build(:mail_queue, params)
    end

    subject { @instance.valid? }

    describe 'timer_at' do
      context do
        let!(:params) { { timer_at: nil } }
        it { is_expected.to be false }
      end

      context do
        let!(:params) { { timer_at: '2023-10-23' } }
        it { is_expected.to be true }
      end
    end

    describe 'envelope_to' do
      context do
        let!(:params) { { envelope_to: nil } }
        it { is_expected.to be false }
      end

      context do
        let!(:params) { { envelope_to: 'to@example.com' } }
        it { is_expected.to be true }
      end
    end
  end




  describe 'インスタンスメソッド' do
    describe '#eml' do
      before do
        @eml_source = FactoryBot.create(:eml_source)
        @instance = FactoryBot.create(:mail_queue, eml_source: @eml_source)
      end

      it '関連する EmlSource の #eml に等しい' do
        expect(@instance.eml).to eq @eml_source.eml
      end
    end
  end
end
