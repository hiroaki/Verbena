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

  describe 'クラスメソッド' do
    describe '.issue_session_id' do
      it '少なくとも 1000 回の試行では重複がないこと' do
        mem = {}
        1.upto(1000) do
          mem[described_class.issue_session_id.to_s.to_sym] = true
        end
        expect(mem.keys.length).to eq 1000
      end
    end

    describe '.engage_by_timer!' do
      before do
        travel_to genzai_jikoku
      end

      context 'session_id が nil の場合' do
        let!(:specific_session_id) { nil }

        it '例外 ArgumentError が投げられる' do
          expect {
            described_class.engage_by_timer!(specific_session_id)
          }.to raise_error(ArgumentError)
        end
      end

      context 'session_id を指定する場合' do
        let!(:specific_session_id) { 'sess' }

        context 'レコードがある場合： session_id が NULL 、 timer_at が現在時刻より前' do
          before do
            @row = FactoryBot.create(:mail_queue, :untouched, timer_at: genzai_jikoku - 1.hour)
            described_class.engage_by_timer!(specific_session_id)
            @row.reload
          end

          it '指定した session_id がレコードにセットされる' do
            expect(@row.session_id).to eq specific_session_id
          end
        end

        context 'レコードがある場合： session_id が NULL 、 timer_at が現在時刻より後' do
          before do
            @row = FactoryBot.create(:mail_queue, :untouched, timer_at: genzai_jikoku + 1.hour)
            described_class.engage_by_timer!(specific_session_id)
            @row.reload
          end

          it '指定した session_id はレコードにセットされない' do
            expect(@row.session_id).to be_nil
          end
        end

        context 'レコードがある場合： session_id が指定するものとは異なり 、 timer_at が現在時刻より前' do
          before do
            @row = FactoryBot.create(:mail_queue, session_id: 'different', timer_at: genzai_jikoku - 1.hour)
            described_class.engage_by_timer!(specific_session_id)
            @row.reload
          end

          it '指定した session_id はレコードにセットされず、元の値のまま' do
            expect(@row.session_id).to eq 'different'
          end
        end

        context 'レコードがある場合： session_id が指定するものとは同じ 、 timer_at が現在時刻より前' do
          before do
            FactoryBot.create(:mail_queue, session_id: specific_session_id, timer_at: genzai_jikoku - 1.hour)
          end

          it '例外 EngageByNotNewSessionError が投げられる' do
            expect {
              described_class.engage_by_timer!(specific_session_id)
            }.to raise_error(MailQueue::EngageByNotNewSessionError)
          end
        end
      end
    end

    describe '.engage_by_id!' do
      before do
        travel_to genzai_jikoku
      end

      context 'session_id が nil の場合' do
        let!(:specific_session_id) { nil }

        it '例外 ArgumentError が投げられる' do
          expect {
            described_class.engage_by_id!(specific_session_id, 1)
          }.to raise_error(ArgumentError)
        end
      end

      context 'session_id を指定する場合' do
        let!(:specific_session_id) { 'sess' }

        # NOTE: .engage_by_id の場合には timer_at の条件は考慮されない仕様なので、
        # ここでは未来の時刻のレコードでも選択されることも同時に確認しています。
        context '未処理のレコードが二つある場合（ session_id が NULL 、 timer_at が現在時刻より未来）' do
          before do
            @row1 = FactoryBot.create(:mail_queue, :untouched, timer_at: genzai_jikoku + 1.hour)
            @row2 = FactoryBot.create(:mail_queue, :untouched, timer_at: genzai_jikoku + 1.hour)
            described_class.engage_by_id!(specific_session_id, specfic_id)
            @row1.reload
            @row2.reload
          end

          context 'レコード(1) の id を指定する場合' do
            let!(:specfic_id) { @row1.id }
            it 'レコード(1) に指定した session_id がレコードにセットされ、レコード(2)にはセットされない' do
              expect(@row1.session_id).to eq specific_session_id
              expect(@row2.session_id).not_to eq specific_session_id
            end
          end
        end

        context '処理済みのレコードがある場合' do
          before do
            @row = FactoryBot.create(:mail_queue, session_id: session_id, timer_at: genzai_jikoku - 1.hour)
          end

          context 'レコードの session_id が、指定する session_id と同じ場合' do
            let!(:session_id) { specific_session_id }
            it '例外 EngageByNotNewSessionError が投げられる' do
              expect {
                described_class.engage_by_id!(specific_session_id, @row.id)
              }.to raise_error(MailQueue::EngageByNotNewSessionError)
            end
          end

          context 'レコードの session_id が、指定する session_id と異なる場合' do
            let!(:session_id) { "not-#{specific_session_id}" }
            it '例外は投げられない' do
              expect { described_class.engage_by_id!(specific_session_id, @row.id) }.not_to raise_error
            end
          end
        end
      end
    end

    describe '.engaged!' do
      before do
        @row1 = FactoryBot.create(:mail_queue, session_id: 'sess')
        @row2 = FactoryBot.create(:mail_queue, session_id: 'other')
        @row3 = FactoryBot.create(:mail_queue, session_id: 'sess')
        @row4 = FactoryBot.create(:mail_queue, session_id: nil)
        @row5 = FactoryBot.create(:mail_queue, session_id: 'sess')
      end

      subject { described_class.engaged(specific_session_id).map(&:id) }

      context '引数 session_id に "sess" を渡す場合' do
        let!(:specific_session_id) { 'sess' }
        it '属性 session_id が "sess" のレコードのリストが得られる' do
          is_expected.to eq([@row1.id, @row3.id, @row5.id])
        end
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
