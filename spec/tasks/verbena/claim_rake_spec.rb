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
      it '解放対象のレコード数を表示し、実際には解放しない' do
        expect { task.invoke(nil, 'true') }.to output(/DRY RUN: Would release 2 stale claims/).to_stdout
        
        # レコードは変更されていない
        @fresh_record.reload
        @stale_record1.reload
        @stale_record2.reload
        
        expect(@fresh_record.session_id).to eq('fresh')
        expect(@stale_record1.session_id).to eq('stale1')
        expect(@stale_record2.session_id).to eq('stale2')
      end
    end

    context 'カスタム時間（0.5時間）で実行する場合' do
      it '指定した時間より古い claim を解放する' do
        expect { task.invoke('0.5', 'false') }.to output(/Released 3 stale claims older than 0.5 hour/).to_stdout
        
        # 30分前のレコードも解放される
        @fresh_record.reload
        @stale_record1.reload
        @stale_record2.reload
        
        expect(@fresh_record.session_id).to be_nil
        expect(@fresh_record.claimed_at).to be_nil
        expect(@stale_record1.session_id).to be_nil
        expect(@stale_record2.session_id).to be_nil
      end
    end

    context '引数なしで実行する場合' do
      it 'デフォルト値（1時間）を使用して実行する' do
        expect { task.invoke }.to output(/Released 2 stale claims older than 1.0 hour/).to_stdout
        
        @fresh_record.reload
        @stale_record1.reload
        @stale_record2.reload
        
        expect(@fresh_record.session_id).to eq('fresh') # 30分前なので残る
        expect(@stale_record1.session_id).to be_nil
        expect(@stale_record2.session_id).to be_nil
      end
    end

    context 'ログ出力の検証' do
      it 'Rails.logger にも適切にログ出力される' do
        expect(Rails.logger).to receive(:info).with(/Would release \d+ stale claims/)
        
        expect { task.invoke(nil, 'true') }.to output(/DRY RUN/).to_stdout
      end
    end
  end

  describe 'verbena:claim:show_stale' do
    let(:task) { Rake::Task['verbena:claim:show_stale'] }

    before do
      task.reenable
    end

    context 'スタックレコードがある場合' do
      before do
        # claim されて配送済み
        delivered = FactoryBot.create(:mail_queue, session_id: 'delivered', claimed_at: 1.hour.ago, envelope_to: 'delivered@example.com')
        FactoryBot.create(:delivery_response, mail_queue: delivered)
        
        # claim されているが未配送（スタック）
        @stale1 = FactoryBot.create(:mail_queue, session_id: 'very_long_session_id_for_truncation_test', 
                                   claimed_at: 2.hours.ago, envelope_to: 'stale1@example.com')
        @stale2 = FactoryBot.create(:mail_queue, session_id: 'stale2', 
                                   claimed_at: 3.hours.ago, envelope_to: 'stale2@example.com')
        
        # 未 claim
        FactoryBot.create(:mail_queue, :untouched, envelope_to: 'unclaimed@example.com')
      end

      it 'スタックレコードの詳細を表示する' do
        output = capture_stdout { task.invoke }
        
        expect(output).to include("Found 2 claimed but undelivered records:")
        expect(output).to include("ID\tSession ID\tClaimed At\tEnvelope To\tAge")
        expect(output).to include("#{@stale1.id}")
        expect(output).to include("#{@stale2.id}")
        expect(output).to include("stale1@example.com")
        expect(output).to include("stale2@example.com")
      end

      it 'session_id を適切に短縮表示する' do
        output = capture_stdout { task.invoke }
        
        # 長い session_id は短縮される
        expect(output).to include("very_long_...")
        # 短い session_id はそのまま表示
        expect(output).to include("stale2")
      end

      it '経過時間を適切にフォーマットして表示する' do
        output = capture_stdout { task.invoke }
        
        # 2時間前と3時間前のレコードがあるので、対応する時間表示があることを確認
        expect(output).to match(/[23]h/)
      end
    end

    context 'スタックレコードがない場合' do
      before do
        # 全て配送済みか未 claim のレコードのみ
        delivered = FactoryBot.create(:mail_queue, session_id: 'delivered', claimed_at: 1.hour.ago)
        FactoryBot.create(:delivery_response, mail_queue: delivered)
        FactoryBot.create(:mail_queue, :untouched)
      end

      it '該当なしのメッセージを表示する' do
        output = capture_stdout { task.invoke }
        expect(output).to include("No stale claimed records found.")
      end
    end
  end

  describe 'ヘルパーメソッド' do
    # Rake タスク内のプライベートメソッドをテスト
    # 実際の rake ファイルを読み込んで定義されたメソッドをテスト

    describe 'truthy?' do
      it '真値文字列を正しく判定する' do
        # Rake タスクファイルが読み込まれた際に定義されるヘルパーメソッドをテスト
        # メソッドはトップレベルで定義されているため、main オブジェクトから呼び出す
        expect(main.send(:truthy?, '1')).to be true
        expect(main.send(:truthy?, 'true')).to be true
        expect(main.send(:truthy?, 'yes')).to be true
        expect(main.send(:truthy?, 'Y')).to be true
        expect(main.send(:truthy?, 'T')).to be true
        expect(main.send(:truthy?, '0')).to be false
        expect(main.send(:truthy?, 'false')).to be false
        expect(main.send(:truthy?, 'no')).to be false
        expect(main.send(:truthy?, nil)).to be false
      end
    end

    describe 'format_duration' do
      it '秒数を適切にフォーマットする' do
        expect(main.send(:format_duration, 0)).to eq("0s")
        expect(main.send(:format_duration, 30)).to eq("0m30s")
        expect(main.send(:format_duration, 90)).to eq("1m30s")
        expect(main.send(:format_duration, 3661)).to eq("1h1m1s")
        expect(main.send(:format_duration, 7200)).to eq("2h0m0s")
      end

      it '1秒未満の場合は0sを返す' do
        expect(main.send(:format_duration, 0.5)).to eq("0s")
        expect(main.send(:format_duration, -1)).to eq("0s")
      end
    end
  end

  private

  def capture_stdout(&block)
    original_stdout = $stdout
    $stdout = fake = StringIO.new
    begin
      yield
    ensure
      $stdout = original_stdout
    end
    fake.string
  end
end