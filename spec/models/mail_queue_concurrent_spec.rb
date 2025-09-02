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
  end
end