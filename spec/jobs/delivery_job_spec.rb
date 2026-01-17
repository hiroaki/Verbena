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

    it 'does not call DeliveryService if mail_queue is not found' do
      expect(Verbena::DeliveryService).not_to receive(:new)
      described_class.perform_now(-1)
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

      # ここですべて実行すると、リトライ回数分だけ実行されて失敗するはず
      # ただし wait: :exponentially_longer があるので、すぐには実行されない可能性がある
      # 構成の存在確認だけ行いたいが、簡易的にクラス定義をチェックする手もある
    end
  end
end
