require 'rails_helper'

RSpec.describe MailQueue, 'concurrent claiming', type: :model do
  let!(:current_time) { Time.zone.parse('2023-10-23 15:30:00') }
  
  before do
    travel_to current_time
  end

  describe 'concurrent claim operations' do
    context '同じ条件で複数のセッションが claim しようとする場合' do
      let!(:available_records) do
        5.times.map do
          FactoryBot.create(:mail_queue, :untouched, timer_at: current_time - 1.hour)
        end
      end

      it '重複して claim されない（基本的な排他制御テスト）' do
        session_id_1 = MailQueue.issue_session_id
        session_id_2 = MailQueue.issue_session_id
        
        # 最初のセッションで claim
        claimed_count_1 = MailQueue.claim_by_timer!(session_id_1)
        
        # 2番目のセッションで claim を試行（残りがあれば取得）
        claimed_count_2 = MailQueue.claim_by_timer!(session_id_2)
        
        # 合計が元のレコード数と一致
        expect(claimed_count_1 + claimed_count_2).to eq(available_records.length)
        
        # それぞれのセッションで取得したレコードに重複がない
        session_1_ids = MailQueue.claimed(session_id_1).pluck(:id)
        session_2_ids = MailQueue.claimed(session_id_2).pluck(:id)
        expect(session_1_ids & session_2_ids).to be_empty
        
        # 全てのレコードがいずれかのセッションに属している
        all_claimed_ids = session_1_ids + session_2_ids
        available_ids = available_records.map(&:id)
        expect(all_claimed_ids.sort).to eq(available_ids.sort)
      end
    end

    context 'バッチサイズを超える数のレコードがある場合' do
      before do
        # バッチサイズより多いレコードを作成
        allow(MailQueue).to receive(:claim_batch_size).and_return(3)
        @large_batch = 7.times.map do
          FactoryBot.create(:mail_queue, :untouched, timer_at: current_time - 1.hour)
        end
      end

      it 'バッチ単位で処理されて全て claim される' do
        session_id = MailQueue.issue_session_id
        claimed_count = MailQueue.claim_by_timer!(session_id)
        
        expect(claimed_count).to eq(@large_batch.length)
        expect(MailQueue.claimed(session_id).count).to eq(@large_batch.length)
        
        # claimed_at が設定されている
        MailQueue.claimed(session_id).each do |record|
          expect(record.claimed_at).to be_within(1.second).of(current_time)
        end
      end
    end
  end

  describe 'stale claim detection and cleanup' do
    context 'claimed_at が古いレコードがある場合' do
      before do
        @fresh_record = FactoryBot.create(:mail_queue, session_id: 'fresh', claimed_at: 30.minutes.ago)
        @stale_record = FactoryBot.create(:mail_queue, session_id: 'stale', claimed_at: 2.hours.ago)
        @very_stale_record = FactoryBot.create(:mail_queue, session_id: 'very_stale', claimed_at: 4.hours.ago)
      end

      it '.release_stale_claims! で古い claim が解放される' do
        released_count = MailQueue.release_stale_claims!(older_than: 1.hour.ago)
        
        expect(released_count).to eq(2)
        
        @fresh_record.reload
        @stale_record.reload
        @very_stale_record.reload
        
        expect(@fresh_record.session_id).to eq('fresh')
        expect(@fresh_record.claimed_at).not_to be_nil
        expect(@stale_record.session_id).to be_nil
        expect(@stale_record.claimed_at).to be_nil
        expect(@very_stale_record.session_id).to be_nil
        expect(@very_stale_record.claimed_at).to be_nil
      end
    end

    context 'claimed_but_undelivered を使った監視' do
      before do
        # claim されて配送済み
        @delivered = FactoryBot.create(:mail_queue, session_id: 'delivered', claimed_at: 1.hour.ago)
        FactoryBot.create(:delivery_response, mail_queue: @delivered)
        
        # claim されているが未配送（問題のあるレコード）
        @problematic1 = FactoryBot.create(:mail_queue, session_id: 'prob1', claimed_at: 2.hours.ago)
        @problematic2 = FactoryBot.create(:mail_queue, session_id: 'prob2', claimed_at: 3.hours.ago)
        
        # 未 claim
        @unclaimed = FactoryBot.create(:mail_queue, :untouched)
      end

      it '配送結果のない claim レコードを特定できる' do
        problematic_ids = MailQueue.claimed_but_undelivered.pluck(:id)
        expect(problematic_ids).to match_array([@problematic1.id, @problematic2.id])
      end

      it '配送済みレコードや未 claim レコードは含まれない' do
        problematic_ids = MailQueue.claimed_but_undelivered.pluck(:id)
        expect(problematic_ids).not_to include(@delivered.id)
        expect(problematic_ids).not_to include(@unclaimed.id)
      end
    end
  end

  describe 'enhanced error handling and retry logic' do
    let(:session_id) { 'retry_test_session' }

    before do
      # テスト用レコードを作成
      @test_records = 3.times.map do
        FactoryBot.create(:mail_queue, :untouched, timer_at: current_time - 1.hour)
      end
    end

    context 'デッドロック発生時のリトライ処理' do
      it 'claim_max_retries の設定値に従ってリトライする' do
        original_max_retries = 2
        allow(MailQueue).to receive(:claim_max_retries).and_return(original_max_retries)
        
        retry_count = 0
        allow(MailQueue).to receive(:where).and_wrap_original do |method, *args|
          retry_count += 1
          result = method.call(*args)
          if retry_count <= original_max_retries - 1
            allow(result).to receive(:limit).and_raise(ActiveRecord::Deadlocked.new("simulated deadlock"))
          end
          result
        end

        expect(Rails.logger).to receive(:warn).exactly(original_max_retries - 1).times
        expect { MailQueue.claim_by_timer!(session_id) }.not_to raise_error
      end

      it 'calculate_backoff_seconds で指定された時間待機する' do
        allow(MailQueue).to receive(:claim_max_retries).and_return(2)
        allow(MailQueue).to receive(:calculate_backoff_seconds).and_return(0.1) # テスト用に短縮

        call_count = 0
        allow(MailQueue).to receive(:where).and_wrap_original do |method, *args|
          call_count += 1
          result = method.call(*args)
          if call_count == 1
            allow(result).to receive(:limit).and_raise(ActiveRecord::Deadlocked.new("simulated deadlock"))
          end
          result
        end

        start_time = Time.current
        MailQueue.claim_by_timer!(session_id)
        elapsed_time = Time.current - start_time

        expect(elapsed_time).to be >= 0.1 # バックオフ時間が考慮されている
      end

      it '最大リトライ回数を超える場合は session_id 付きエラーログを出力する' do
        allow(MailQueue).to receive(:claim_max_retries).and_return(2)
        allow(MailQueue).to receive(:where) do
          double.tap do |mock|
            allow(mock).to receive(:limit).and_raise(ActiveRecord::LockWaitTimeout.new("persistent timeout"))
          end
        end

        expect(Rails.logger).to receive(:error).with(
          match(/Max retries exceeded for claim operation for session_id=\[#{session_id}\]:.*persistent timeout/)
        )

        expect {
          MailQueue.claim_by_timer!(session_id)
        }.to raise_error(ActiveRecord::LockWaitTimeout)
      end
    end

    context '一貫したタイムスタンプの使用' do
      it '同一セッション内の全レコードが同じ claimed_at を持つ' do
        # バッチサイズを小さくして複数回のバッチ処理を発生させる
        allow(MailQueue).to receive(:claim_batch_size).and_return(2)
        
        # 異なる時間を返すように Time.current をモック
        time_sequence = [current_time, current_time + 1.second, current_time + 2.seconds]
        allow(Time).to receive(:current).and_return(*time_sequence)

        MailQueue.claim_by_timer!(session_id)

        claimed_records = MailQueue.claimed(session_id)
        claimed_times = claimed_records.pluck(:claimed_at).uniq
        
        # 全て同じ時刻（最初に取得した時刻）であることを確認
        expect(claimed_times.length).to eq(1)
        expect(claimed_times.first).to eq(current_time)
      end
    end

    context 'バッチサイズ設定の動作検証' do
      it 'claim_batch_size の設定値に従ってバッチ処理する' do
        custom_batch_size = 2
        allow(MailQueue).to receive(:claim_batch_size).and_return(custom_batch_size)
        
        # update_all が適切な回数呼ばれることを検証
        expect(MailQueue).to receive(:update_all).exactly(2).times.and_call_original # 3レコード ÷ 2バッチサイズ = 2回
        
        claimed_count = MailQueue.claim_by_timer!(session_id)
        expect(claimed_count).to eq(@test_records.length)
      end
    end
  end
end