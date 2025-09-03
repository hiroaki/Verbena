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

      it 'left_outer_joins を使用して正しいクエリを実行する' do
        expect(described_class).to receive(:left_outer_joins).with(:delivery_responses).and_call_original
        described_class.claimed_but_undelivered.to_a
      end

      it '複数の配送結果がある場合も正しく動作する' do
        # 複数の配送結果を持つレコード
        multi_delivered = FactoryBot.create(:mail_queue, session_id: 'multi')
        FactoryBot.create(:delivery_response, mail_queue: multi_delivered)
        FactoryBot.create(:delivery_response, mail_queue: multi_delivered)
        
        expect(described_class.claimed_but_undelivered.map(&:id)).to match_array([@stale_row1.id, @stale_row2.id])
      end
    end

    describe '.claim_max_retries' do
      it 'デフォルト値5を返す' do
        expect(described_class.send(:claim_max_retries)).to eq(5)
      end
    end

    describe '.calculate_backoff_seconds' do
      it 'retry_count に関係なく1秒を返す' do
        expect(described_class.send(:calculate_backoff_seconds, 0)).to eq(1)
        expect(described_class.send(:calculate_backoff_seconds, 1)).to eq(1)
        expect(described_class.send(:calculate_backoff_seconds, 4)).to eq(1)
      end
    end

    describe '.claim_batch_size' do
      it 'Verbena::Settings から設定値を取得する' do
        expect(Verbena::Settings).to receive(:in_batches_config).and_return({ of: 25 })
        expect(described_class.send(:claim_batch_size)).to eq(25)
      end

      it '設定がない場合はデフォルト値20を返す' do
        expect(Verbena::Settings).to receive(:in_batches_config).and_return({})
        expect(described_class.send(:claim_batch_size)).to eq(20)
      end
    end

    describe '.claim_in_batches' do
      let(:session_id) { 'test_session' }
      let(:condition) { { timer_at: Time.current } }

      before do
        travel_to genzai_jikoku
        # テスト用のレコードを作成
        @rows = 3.times.map do |i|
          FactoryBot.create(:mail_queue, :untouched, timer_at: genzai_jikoku - 1.hour)
        end
      end

      it '正常時に claim 処理を実行し、処理したレコード数を返す' do
        allow(described_class).to receive(:claim_batch_size).and_return(5)
        result = described_class.send(:claim_in_batches, session_id, condition.merge(timer_at: ..genzai_jikoku))
        
        expect(result).to eq(3)
        @rows.each do |row|
          row.reload
          expect(row.session_id).to eq(session_id)
          expect(row.claimed_at).to be_within(1.second).of(genzai_jikoku)
        end
      end

      it 'バッチサイズに従って処理を実行する' do
        allow(described_class).to receive(:claim_batch_size).and_return(2)
        allow(described_class).to receive(:claim_max_retries).and_return(5)
        
        result = described_class.send(:claim_in_batches, session_id, condition.merge(timer_at: ..genzai_jikoku))
        
        expect(result).to eq(3) # 2 + 1 のバッチで3レコード処理
      end

      context 'デッドロック発生時' do
        before do
          allow(described_class).to receive(:claim_batch_size).and_return(5)
          allow(described_class).to receive(:claim_max_retries).and_return(3)
        end

        it 'リトライ回数内でリカバリできる場合は成功する' do
          call_count = 0
          allow(described_class).to receive(:where).and_wrap_original do |method, *args|
            call_count += 1
            result = method.call(*args)
            if call_count == 1
              # 最初の呼び出しでデッドロックをシミュレート
              allow(result).to receive(:limit).and_raise(ActiveRecord::Deadlocked.new("deadlock"))
            end
            result
          end

          expect(Rails.logger).to receive(:warn).with(/Deadlock detected during claim, retrying/)
          expect { described_class.send(:claim_in_batches, session_id, condition.merge(timer_at: ..genzai_jikoku)) }.not_to raise_error
        end

        it 'リトライ最大回数を超える場合はエラーログを出力して例外を発生させる' do
          allow(described_class).to receive(:where) do
            double.tap do |mock|
              allow(mock).to receive(:limit).and_raise(ActiveRecord::Deadlocked.new("persistent deadlock"))
            end
          end

          expect(Rails.logger).to receive(:warn).exactly(2).times # max_retries - 1 回のwarning
          expect(Rails.logger).to receive(:error).with(/Max retries exceeded for claim operation for session_id=\[#{session_id}\]:/)
          
          expect {
            described_class.send(:claim_in_batches, session_id, condition.merge(timer_at: ..genzai_jikoku))
          }.to raise_error(ActiveRecord::Deadlocked)
        end
      end

      it '同一セッション内で一貫したタイムスタンプを使用する' do
        freeze_time = genzai_jikoku
        allow(Time).to receive(:current).and_return(freeze_time, freeze_time + 1.second, freeze_time + 2.seconds)
        allow(described_class).to receive(:claim_batch_size).and_return(2)
        
        described_class.send(:claim_in_batches, session_id, condition.merge(timer_at: ..genzai_jikoku))
        
        @rows.each do |row|
          row.reload
          expect(row.claimed_at).to eq(freeze_time) # 全て同じタイムスタンプ
        end
      end
    end

    describe '.claim!' do
      let(:session_id) { 'integration_test_session' }

      before do
        travel_to genzai_jikoku
        # 複数のレコードを作成してバッチ処理をテスト
        @test_rows = 25.times.map do |i|
          FactoryBot.create(:mail_queue, :untouched, timer_at: genzai_jikoku - 1.hour)
        end
      end

      it 'claim_in_batches を使用して処理する' do
        expect(described_class).to receive(:claim_in_batches).with(session_id, anything).and_call_original
        described_class.send(:claim!, session_id, timer_at: ..genzai_jikoku)
      end

      it 'claim_max_retries の設定を使用する' do
        # デッドロックを引き起こす設定
        allow(described_class).to receive(:where) do
          double.tap do |mock|
            allow(mock).to receive(:limit).and_raise(ActiveRecord::Deadlocked.new("deadlock"))
          end
        end

        expect(described_class).to receive(:claim_max_retries).and_return(2)
        expect(Rails.logger).to receive(:warn).exactly(1).times # max_retries - 1
        expect(Rails.logger).to receive(:error).with(/Max retries exceeded for claim operation for session_id=\[#{session_id}\]:/)

        expect {
          described_class.send(:claim!, session_id, timer_at: ..genzai_jikoku)
        }.to raise_error(ActiveRecord::Deadlocked)
      end

      it 'バッチサイズの設定を使用して処理する' do
        allow(described_class).to receive(:claim_batch_size).and_return(10)
        
        # バッチサイズが10なので、25レコードは3回のバッチで処理される
        expect(described_class).to receive(:update_all).exactly(3).times.and_call_original
        
        result = described_class.send(:claim!, session_id, timer_at: ..genzai_jikoku)
        expect(result).to eq(25)
      end
    end

    describe 'エラーハンドリングとログ出力の統合テスト' do
      let(:session_id) { 'error_test_session' }

      before do
        travel_to genzai_jikoku
        FactoryBot.create(:mail_queue, :untouched, timer_at: genzai_jikoku - 1.hour)
      end

      it 'session_id を含むエラーメッセージが出力される' do
        allow(described_class).to receive(:where) do
          double.tap do |mock|
            allow(mock).to receive(:limit).and_raise(ActiveRecord::LockWaitTimeout.new("lock timeout"))
          end
        end

        expect(Rails.logger).to receive(:error).with(
          match(/Max retries exceeded for claim operation for session_id=\[#{session_id}\]:.*lock timeout/)
        )

        expect {
          described_class.send(:claim!, session_id, timer_at: ..genzai_jikoku)
        }.to raise_error(ActiveRecord::LockWaitTimeout)
      end

      it '警告ログにリトライ情報が含まれる' do
        call_count = 0
        allow(described_class).to receive(:where).and_wrap_original do |method, *args|
          call_count += 1
          result = method.call(*args)
          if call_count <= 2
            allow(result).to receive(:limit).and_raise(ActiveRecord::Deadlocked.new("deadlock"))
          end
          result
        end

        expect(Rails.logger).to receive(:warn).with(
          match(/Deadlock detected during claim, retrying in 1s \(attempt [12]\/5\)/)
        ).exactly(2).times

        expect { described_class.send(:claim!, session_id, timer_at: ..genzai_jikoku) }.not_to raise_error
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
