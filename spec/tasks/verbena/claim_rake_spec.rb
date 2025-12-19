require 'rails_helper'
require 'rake'

RSpec.describe 'verbena:claim rake tasks' do
  let!(:current_time) { Time.zone.parse('2023-10-23 16:00:00') }

  before do
    travel_to current_time
    Rake.application.rake_require 'tasks/verbena/claim'
    Rake::Task.define_task(:environment)
  end

  describe 'verbena:claim:release_stale' do
    let(:task) { Rake::Task['verbena:claim:release_stale'] }

    before do
      task.reenable # タスクを再実行可能にする
      
      # テストデータを作成
      @fresh_record = FactoryBot.create(:mail_queue, session_id: 'fresh', claimed_at: 30.minutes.ago)
      @stale_record1 = FactoryBot.create(:mail_queue, session_id: 'stale1', claimed_at: 2.hours.ago)
      @stale_record2 = FactoryBot.create(:mail_queue, session_id: 'stale2', claimed_at: 3.hours.ago)
      @unclaimed_record = FactoryBot.create(:mail_queue, :untouched)
    end

    context 'デフォルト設定（1時間）でドライランの場合' do
      it 'true を渡すと解放対象の件数のみを表示（変更なし）' do
        expect { task.invoke(nil, 'true') }.to output(/DRY RUN: Would release 2 stale claims/).to_stdout
        
        # レコードは変更されていない
        @fresh_record.reload
        @stale_record1.reload
        @stale_record2.reload
        
        expect(@fresh_record.session_id).to eq('fresh')
        expect(@stale_record1.session_id).to eq('stale1')
        expect(@stale_record2.session_id).to eq('stale2')
      end

      it 'on を渡しても true と同じ挙動（ActiveModel::Boolean）' do
        task.reenable
        expect { task.invoke(nil, 'on') }.to output(/DRY RUN: Would release 2 stale claims/).to_stdout
      end
    end

    context '実際に解放を実行する場合' do
      it '指定した時間より古い claim を解放する' do
        task.reenable
        expect { task.invoke('1.5', 'false') }.to output(/Released 2 stale claims older than 1.5 hour/).to_stdout
        
        # 1.5時間より古いレコードが解放される
        @fresh_record.reload
        @stale_record1.reload
        @stale_record2.reload
        
        expect(@fresh_record.session_id).to eq('fresh')  # 30分前なので残る
        expect(@stale_record1.session_id).to be_nil      # 2時間前なので解放
        expect(@stale_record2.session_id).to be_nil      # 3時間前なので解放
      end
    end
  end

  describe 'verbena:claim:show_stale' do
    let(:task) { Rake::Task['verbena:claim:show_stale'] }

    before do
      task.reenable
    end

    context 'スタック状態のレコードがある場合' do
      before do
        @stale_record = FactoryBot.create(:mail_queue, session_id: 'stale123', 
                                        claimed_at: 1.hour.ago, envelope_to: 'test@example.com')
        FactoryBot.create(:mail_queue, :untouched, envelope_to: 'unclaimed@example.com')
      end

      it 'スタック状態のレコード情報を表示する' do
        expect { task.invoke }.to output(/Found 1 claimed but undelivered records/).to_stdout
      end
    end

    context 'スタック状態のレコードがない場合' do
      before do
        FactoryBot.create(:mail_queue, :untouched)
      end

      it '対象レコードなしのメッセージを表示する' do
        expect { task.invoke }.to output(/No stale claimed records found/).to_stdout
      end
    end
  end
end