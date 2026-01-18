require 'rails_helper'
require 'rake'

RSpec.describe 'verbena:delivery rake tasks' do
  let!(:current_time) { Time.zone.parse('2023-10-23 16:00:00') }

  before do
    ActiveJob::Base.queue_adapter = :test
    travel_to current_time
    # Recreate Rake.application per example to avoid task definitions leaking
    # between examples (Rake.application is global). This ensures each example
    # loads a fresh task set and `task.reenable` works reliably.
    Rake.application = Rake::Application.new
    load Rails.root.join('lib', 'tasks', 'verbena', 'delivery.rake')
    Rake::Task.define_task(:environment)
  end

  after do
    travel_back
  end

  describe 'verbena:delivery:prepare_retry' do
    let(:task) { Rake::Task['verbena:delivery:prepare_retry'] }

    before do
      task.reenable
    end

    context 'when retryable messages exist' do
      let!(:mq1) { FactoryBot.create(:mail_queue, :touched) }
      let!(:mq2) { FactoryBot.create(:mail_queue, :touched) }
      let!(:mq3) { FactoryBot.create(:mail_queue, :touched) }
      let!(:mq4) { FactoryBot.create(:mail_queue, :touched) }

      before do
        FactoryBot.create(:delivery_response, mail_queue_id: mq1.id, responded_at: current_time - 2.hour, created_at: current_time - 2.hour, status: '400')
        FactoryBot.create(:delivery_response, mail_queue_id: mq2.id, responded_at: current_time - 3.hour, created_at: current_time - 3.hour, status: '400')
        FactoryBot.create(:delivery_response, mail_queue_id: mq2.id, responded_at: current_time - 2.hour, created_at: current_time - 2.hour, status: '250')
        FactoryBot.create(:delivery_response, mail_queue_id: mq3.id, responded_at: current_time - 2.hour, created_at: current_time - 2.hour, status: '250')
        FactoryBot.create(:delivery_response, mail_queue_id: mq4.id, responded_at: current_time - 4.hour, created_at: current_time - 4.hour, status: '400')
      end

      it 'enqueues jobs for retryable messages (4xx status) and prints count' do
        task.reenable
        # mq1: last status 400 -> Retry
        # mq2: last status 250 -> OK
        # mq3: last status 250 -> OK
        # mq4: last status 400 -> Retry
        # Total 2 jobs to enqueue
        expect {
          expect { task.invoke }.to output(/Enqueued 2 jobs for retry/).to_stdout
        }.to have_enqueued_job(DeliveryJob).exactly(2).times
      end
    end
  end

  describe 'verbena:delivery:reset_undelivered' do
    let(:task) { Rake::Task['verbena:delivery:reset_undelivered'] }

    before do
      task.reenable
    end

    context 'when undelivered messages exist' do
      let!(:mq1) { FactoryBot.create(:mail_queue, timer_at: current_time - 25.hours) }
      let!(:mq2) { FactoryBot.create(:mail_queue, timer_at: current_time - 23.hours) }
      let!(:mq3) { FactoryBot.create(:mail_queue, timer_at: current_time - 30.hours) }

      before do
        # mq1 has no delivery_responses, old -> Reset (default 24h)
        # mq2 has no delivery_responses, new -> Skip (default 24h)
        mq3.delivery_responses.create! # has response -> Skip
      end

      it 'enqueues jobs for undelivered messages older than threshold and prints count' do
        task.reenable
        expect {
          expect { task.invoke }.to output(/Enqueued 1 job for undelivered/).to_stdout
        }.to have_enqueued_job(DeliveryJob).exactly(1).times
      end

      it 'accepts argument for threshold' do
        task.reenable
        # Threshold 22h -> mq1(25h), mq2(23h) both reset
        expect {
          expect { task.invoke('22') }.to output(/Enqueued 2 jobs for undelivered/).to_stdout
        }.to have_enqueued_job(DeliveryJob).exactly(2).times
      end
    end

    context 'when invalid argument is passed' do
      it 'raises ArgumentError for non-numeric argument' do
        task.reenable
        expect { task.invoke('abc') }.to raise_error(ArgumentError, /older_than_hours must be a non-negative integer number of hours/)
      end
    end
  end
end
