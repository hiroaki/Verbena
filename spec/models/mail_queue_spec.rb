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

    describe '.claim_by_timer!' do
      before do
        travel_to genzai_jikoku
      end

      context 'session_id が nil の場合' do
        let!(:specific_session_id) { nil }

        it '例外 ArgumentError が投げられる' do
          expect {
            described_class.claim_by_timer!(specific_session_id)
          }.to raise_error(ArgumentError)
        end
      end

      context 'session_id を指定する場合' do
        let!(:specific_session_id) { 'sess' }

        context 'レコードがある場合： session_id が NULL 、 timer_at が現在時刻より前' do
          before do
            @row = FactoryBot.create(:mail_queue, :untouched, timer_at: genzai_jikoku - 1.hour)
            described_class.claim_by_timer!(specific_session_id)
            @row.reload
          end

          it '指定した session_id がレコードにセットされる' do
            expect(@row.session_id).to eq specific_session_id
          end

          it 'claimed_at が現在時刻にセットされる' do
            expect(@row.claimed_at).to be_within(1.second).of(genzai_jikoku)
          end
        end

        context 'レコードがある場合： session_id が NULL 、 timer_at が現在時刻より後' do
          before do
            @row = FactoryBot.create(:mail_queue, :untouched, timer_at: genzai_jikoku + 1.hour)
            described_class.claim_by_timer!(specific_session_id)
            @row.reload
          end

          it '指定した session_id はレコードにセットされない' do
            expect(@row.session_id).to be_nil
          end
        end

        context 'レコードがある場合： session_id が指定するものとは異なり 、 timer_at が現在時刻より前' do
          before do
            @row = FactoryBot.create(:mail_queue, session_id: 'different', timer_at: genzai_jikoku - 1.hour)
            described_class.claim_by_timer!(specific_session_id)
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

          it '例外 ClaimByNotNewSessionError が投げられる' do
            expect {
              described_class.claim_by_timer!(specific_session_id)
            }.to raise_error(MailQueue::ClaimByNotNewSessionError)
          end
        end
      end
    end

    describe '.claim_by_id!' do
      before do
        travel_to genzai_jikoku
      end

      context 'session_id が nil の場合' do
        let!(:specific_session_id) { nil }

        it '例外 ArgumentError が投げられる' do
          expect {
            described_class.claim_by_id!(specific_session_id, 1)
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
            described_class.claim_by_id!(specific_session_id, specfic_id)
            @row1.reload
            @row2.reload
          end

          context 'レコード(1) の id を指定する場合' do
            let!(:specfic_id) { @row1.id }
            it 'レコード(1) に指定した session_id がレコードにセットされ、レコード(2)にはセットされない' do
              expect(@row1.session_id).to eq specific_session_id
              expect(@row1.claimed_at).to be_within(1.second).of(genzai_jikoku)
              expect(@row2.session_id).not_to eq specific_session_id
              expect(@row2.claimed_at).to be_nil
            end
          end
        end

        context '処理済みのレコードがある場合' do
          before do
            @row = FactoryBot.create(:mail_queue, session_id: session_id, timer_at: genzai_jikoku - 1.hour)
          end

          context 'レコードの session_id が、指定する session_id と同じ場合' do
            let!(:session_id) { specific_session_id }
            it '例外 ClaimByNotNewSessionError が投げられる' do
              expect {
                described_class.claim_by_id!(specific_session_id, @row.id)
              }.to raise_error(MailQueue::ClaimByNotNewSessionError)
            end
          end

          context 'レコードの session_id が、指定する session_id と異なる場合' do
            let!(:session_id) { "not-#{specific_session_id}" }
            it '例外は投げられない' do
              expect { described_class.claim_by_id!(specific_session_id, @row.id) }.not_to raise_error
            end
          end
        end
      end
    end

    describe '.claimed!' do
      before do
        @row1 = FactoryBot.create(:mail_queue, session_id: 'sess')
        @row2 = FactoryBot.create(:mail_queue, session_id: 'other')
        @row3 = FactoryBot.create(:mail_queue, session_id: 'sess')
        @row4 = FactoryBot.create(:mail_queue, session_id: nil)
        @row5 = FactoryBot.create(:mail_queue, session_id: 'sess')
      end

      subject { described_class.claimed(specific_session_id).map(&:id) }

      context '引数 session_id に "sess" を渡す場合' do
        let!(:specific_session_id) { 'sess' }
        it '属性 session_id が "sess" のレコードのリストが得られる' do
          is_expected.to eq([@row1.id, @row3.id, @row5.id])
        end
      end
    end

    describe '.calculate_backoff_seconds' do
      it 'returns a non-negative Float' do
        expect(described_class.send(:calculate_backoff_seconds, 0)).to be >= 0.0
      end

      it 'increases the possible max delay exponentially but capped' do
        # retry 0 -> max_delay == base
        base = 1.0
        cap  = 300.0

        # For retry_count small, max delay should be base * 2**n
        max0 = [base * (2 ** 0), cap].min
        max1 = [base * (2 ** 1), cap].min
        max2 = [base * (2 ** 2), cap].min

        # stub the randomness via the class helper for deterministic assertions
        allow(described_class).to receive(:random_fraction).and_return(0.0)
        expect(described_class.send(:calculate_backoff_seconds, 0)).to eq 0.0
        expect(described_class.send(:calculate_backoff_seconds, 1)).to eq 0.0

        allow(described_class).to receive(:random_fraction).and_return(0.999)
        expect(described_class.send(:calculate_backoff_seconds, 0)).to be_within(0.01).of(max0 * 0.999)
        expect(described_class.send(:calculate_backoff_seconds, 1)).to be_within(0.01).of(max1 * 0.999)
        expect(described_class.send(:calculate_backoff_seconds, 2)).to be_within(0.01).of(max2 * 0.999)

        # And when retry_count is large, ensure cap applies
        large_retry = 100
        allow(described_class).to receive(:random_fraction).and_return(0.5)
        expect(described_class.send(:calculate_backoff_seconds, large_retry)).to be <= cap
        allow(described_class).to receive(:random_fraction).and_call_original
      end
    end

    describe '.release_stale_claims!' do
      let!(:current_time) { Time.zone.parse('2023-10-23 12:00:00') }

      before do
        travel_to current_time
        # 古い claim（2時間前）
        @stale_row1 = FactoryBot.create(:mail_queue, session_id: 'stale1', claimed_at: 2.hours.ago)
        @stale_row2 = FactoryBot.create(:mail_queue, session_id: 'stale2', claimed_at: 90.minutes.ago)
        # 新しい claim（30分前）
        @fresh_row = FactoryBot.create(:mail_queue, session_id: 'fresh', claimed_at: 30.minutes.ago)
        # claim されていない
        @unclaimed_row = FactoryBot.create(:mail_queue, session_id: nil, claimed_at: nil)
      end

      context 'デフォルト（1時間前より古い）で実行する場合' do
        it '1時間より古い claim が解放される' do
          expect {
            described_class.release_stale_claims!
          }.to change { described_class.where(session_id: nil).count }.by(2)

          @stale_row1.reload
          @stale_row2.reload
          @fresh_row.reload
          @unclaimed_row.reload

          expect(@stale_row1.session_id).to be_nil
          expect(@stale_row1.claimed_at).to be_nil
          expect(@stale_row2.session_id).to be_nil
          expect(@stale_row2.claimed_at).to be_nil
          expect(@fresh_row.session_id).to eq('fresh')
          expect(@fresh_row.claimed_at).not_to be_nil
          expect(@unclaimed_row.session_id).to be_nil
        end

        it '解放されたレコード数を返す' do
          result = described_class.release_stale_claims!
          expect(result).to eq(2)
        end
      end

      context 'カスタム時間（30分前）を指定する場合' do
        it '30分より古い claim が解放される' do
          expect {
            described_class.release_stale_claims!(older_than: 30.minutes.ago)
          }.to change { described_class.where(session_id: nil).count }.by(3)
        end
      end
    end

    describe '.claimed_but_undelivered' do
      before do
        # claim されて配送済み
        @delivered_row = FactoryBot.create(:mail_queue, session_id: 'sess1')
        FactoryBot.create(:delivery_response, mail_queue: @delivered_row)

        # claim されているが未配送
        @stale_row1 = FactoryBot.create(:mail_queue, session_id: 'sess2')
        @stale_row2 = FactoryBot.create(:mail_queue, session_id: 'sess3')

        # claim されていない
        @unclaimed_row = FactoryBot.create(:mail_queue, session_id: nil)
      end

      subject { described_class.claimed_but_undelivered.map(&:id) }

      it 'claim されているが配送結果がないレコードを返す' do
        is_expected.to match_array([@stale_row1.id, @stale_row2.id])
      end



      it '複数の配送結果がある場合も正しく動作する' do
        # 複数の配送結果を持つレコード
        multi_delivered = FactoryBot.create(:mail_queue, session_id: 'multi')
        FactoryBot.create(:delivery_response, mail_queue: multi_delivered)
        FactoryBot.create(:delivery_response, mail_queue: multi_delivered)

        expect(described_class.claimed_but_undelivered.map(&:id)).to match_array([@stale_row1.id, @stale_row2.id])
      end
    end

    # Integration tests for concurrent claim functionality
    describe 'concurrent claim execution' do
      let(:session_id_1) { 'session_1' }
      let(:session_id_2) { 'session_2' }

      before do
        travel_to genzai_jikoku
        # 複数のレコードを作成してconcurrency テストを実行
        @available_records = 5.times.map do
          FactoryBot.create(:mail_queue, :untouched, timer_at: genzai_jikoku - 1.hour)
        end
      end

      it '同時実行時に重複してclaimされない' do
        # 最初のセッションでclaim
        claimed_count_1 = MailQueue.claim_by_timer!(session_id_1)

        # 2番目のセッションでclaim（残りがあれば取得）
        claimed_count_2 = MailQueue.claim_by_timer!(session_id_2)

        # 合計が元のレコード数と一致
        expect(claimed_count_1 + claimed_count_2).to eq(@available_records.length)

        # それぞれのセッションのレコードに重複がない
        session_1_ids = MailQueue.claimed(session_id_1).pluck(:id)
        session_2_ids = MailQueue.claimed(session_id_2).pluck(:id)
        expect(session_1_ids & session_2_ids).to be_empty
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
