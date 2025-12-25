require 'rails_helper'
require 'rake'

RSpec.describe 'verbena:delivery rake tasks' do
  let!(:current_time) { Time.zone.parse('2023-10-23 16:00:00') }

  before do
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

    context 'when session_id is missing' do
      it 'prints an error to stderr and calls exit(1) without killing the process' do
        task.reenable
        allow(Kernel).to receive(:exit)  # stub to prevent process termination
        expect { task.invoke(nil) }.to output(/ERROR: prepare_retry failed/).to_stderr
        expect(Kernel).to have_received(:exit).with(1)
      end
    end

    context 'when valid session_id and timelimit provided' do
      let!(:mq1) { FactoryBot.create(:mail_queue, :touched, session_id: 'sess') }
      let!(:mq2) { FactoryBot.create(:mail_queue, :touched, session_id: 'sess') }
      let!(:mq3) { FactoryBot.create(:mail_queue, :touched, session_id: 'sess') }
      let!(:mq4) { FactoryBot.create(:mail_queue, :touched, session_id: 'sess') }

      before do
        FactoryBot.create(:delivery_response, mail_queue_id: mq1.id, responded_at: current_time - 2.hour, status: '400')
        FactoryBot.create(:delivery_response, mail_queue_id: mq2.id, responded_at: current_time - 3.hour, status: '400')
        FactoryBot.create(:delivery_response, mail_queue_id: mq2.id, responded_at: current_time - 2.hour, status: '250')
        FactoryBot.create(:delivery_response, mail_queue_id: mq3.id, responded_at: current_time - 2.hour, status: '250')
        FactoryBot.create(:delivery_response, mail_queue_id: mq4.id, responded_at: current_time - 4.hour, status: '400')
      end

      it 'prints the number of reset mail_queues to stdout' do
        task.reenable
        # Use timelimit 03:00:00 so only mq1 is within window
        expect { task.invoke('sess', '03:00:00') }.to output(/prepare_retry: reset 1 mail_queues for session_id=sess/).to_stdout
      end
    end
  end

  describe 'verbena:delivery:reset_undelivered' do
    let(:task) { Rake::Task['verbena:delivery:reset_undelivered'] }

    before do
      task.reenable
    end

    context 'when session_id is missing' do
      it 'prints an error to stderr and calls exit(1) without killing the process' do
        task.reenable
        allow(Kernel).to receive(:exit)  # stub to prevent process termination
        expect { task.invoke(nil) }.to output(/ERROR: reset_undelivered failed/).to_stderr
        expect(Kernel).to have_received(:exit).with(1)
      end
    end

    context 'when valid session_id provided' do
      let!(:mq1) { FactoryBot.create(:mail_queue, session_id: 'something') }
      let!(:mq2) { FactoryBot.create(:mail_queue, session_id: 'something') }
      let!(:mq3) { FactoryBot.create(:mail_queue, session_id: 'other') }

      before do
        # mq1 has no delivery_responses (should be reset)
        mq2.delivery_responses.create!
      end

      it 'prints the number of reset mail_queues to stdout' do
        task.reenable
        expect { task.invoke('something') }.to output(/reset_undelivered: reset 1 mail_queues for session_id=something/).to_stdout
      end
    end
  end
end
