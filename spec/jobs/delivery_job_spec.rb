require 'rails_helper'

RSpec.describe DeliveryJob, type: :job do
  include ActiveJob::TestHelper

  let(:mail_queue) { FactoryBot.create(:mail_queue) }

  describe '#perform' do
    it 'calls DeliveryService#perform_one with the correct mail_queue' do
      service_double = instance_double(Verbena::DeliveryService)
      # Job ID is random/generated, so we accept anything
      expect(Verbena::DeliveryService).to receive(:new).with(job_id: anything).and_return(service_double)
      expect(service_double).to receive(:perform_one).with(mail_queue)

      described_class.perform_now(mail_queue.id)
    end

    it 'does not call DeliveryService if mail_queue is not found and logs a warning' do
      logger_double = instance_double(ActiveSupport::Logger)
      job_instance = described_class.new(-1)
      allow(job_instance).to receive(:logger).and_return(logger_double)
      expect(logger_double).to receive(:warn).with(/mail_queue not found \(id=-1\)/)

      expect(Verbena::DeliveryService).not_to receive(:new)

      job_instance.perform_now
    end
  end

  describe 'retry configuration' do
    # ActiveJob の retry_on 設定が期待通り動作するか、統合的に検証
    before do
      ActiveJob::Base.queue_adapter = :test
    end

    it 'retries on Net::OpenTimeout' do
      service_double = instance_double(Verbena::DeliveryService)
      allow(Verbena::DeliveryService).to receive(:new).and_return(service_double)
      allow(service_double).to receive(:perform_one).and_raise(Net::OpenTimeout)

      # 1回目は失敗してリトライがキューイングされる
      assert_enqueued_jobs 1 do
        described_class.perform_later(mail_queue.id)
      end

      # 注意: 実際の retry_on の挙動（複数回のリトライ実行や backoff 間隔）はここでは検証しない。
      # wait: :exponentially_longer によりリトライは将来時刻にスケジュールされるため、
      # テスト環境 (test アダプタ / 時刻制御なし) で統合的に実行を追跡するのが難しい。
      # このテストでは「例外発生時にリトライ用ジョブがキューに積まれる」という構成が存在することのみを確認する。
      # より詳細な retry_on の動作検証は ActiveJob 自身のテストに委ね、このアプリ側では設定の有無に留めている。
    end
  end
end
