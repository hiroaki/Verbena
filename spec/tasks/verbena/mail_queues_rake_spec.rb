require 'rails_helper'
require 'rake'

RSpec.describe 'verbena:mail_queues tasks' do
  let(:token) { FactoryBot.create(:token, key: 'sekret') }

  before do
    # Recreate Rake.application per example to avoid task definitions leaking
    # between examples (Rake.application is global). This ensures each example
    # loads a fresh task set and `task.reenable` works reliably.
    Rake.application = Rake::Application.new
    load Rails.root.join('lib', 'tasks', 'verbena', 'mail_queues.rake')
    Rake::Task.define_task(:environment)
  end

  let(:task_add) { Rake::Task['verbena:mail_queues:add'] }
  let(:task_add_raw) { Rake::Task['verbena:mail_queues:add_raw'] }
  let(:task_delete) { Rake::Task['verbena:mail_queues:delete'] }

  before do
    task_add.reenable
    task_add_raw.reenable
    task_delete.reenable
    allow(Token).to receive(:authenticate).and_return(token)
    ENV['VERBENA_TOKEN'] = 'sekret'
  end

  after do
    ENV.delete('VERBENA_TOKEN')
  end

  describe 'parse_extras helper' do
    it 'warns when positional arguments without colon are provided' do
      file = Tempfile.new(['test', '.eml'])
      begin
        file.write("From: example\n\nHello")
        file.close

        allow_any_instance_of(Verbena::MailQueuesService).to receive(:create_mail_queues_from_file!).and_return([1])

        expect {
          task_add.invoke(file.path, 'SOMETOKEN')
        }.to output(/WARNING: Ignoring argument 'SOMETOKEN' - expected key:value format/).to_stderr

      ensure
        file.unlink
      end
    end

    it 'accepts key:value format without warnings' do
      file = Tempfile.new(['test', '.eml'])
      begin
        file.write("From: example\n\nHello")
        file.close

        allow_any_instance_of(Verbena::MailQueuesService).to receive(:create_mail_queues_from_file!).and_return([1])

        expect {
          task_add.invoke(file.path, 'token:SOMETOKEN')
        }.not_to output(/WARNING/).to_stderr

      ensure
        file.unlink
      end
    end
  end

  describe 'add' do

    it 'prints error and calls exit when eml path is missing' do
      allow(Kernel).to receive(:exit)

      expect {
        task_add.invoke(nil)
      }.to output(/ERROR: verbena:mail_queues:add failed/).to_stderr

      expect(Kernel).to have_received(:exit).with(1)
    end

    it 'prints error and calls exit when file not found' do
      allow(Kernel).to receive(:exit)

      expect {
        task_add.invoke('/path/does/not/exist.eml')
      }.to output(/ERROR: verbena:mail_queues:add failed/).to_stderr

      expect(Kernel).to have_received(:exit).with(1)
    end

    it 'succeeds with a valid file' do
      file = Tempfile.new(['test', '.eml'])
      begin
        file.write("From: example\n\nHello")
        file.close

        allow_any_instance_of(Verbena::MailQueuesService).to receive(:create_mail_queues_from_file!).and_return([1])

        expect {
          task_add.invoke(file.path)
        }.to output(/Successfully added \d+ mail_queue\(s\) from #{Regexp.escape(file.path)}/).to_stdout
      ensure
        file.unlink
      end
    end
  end

  describe 'add_raw' do
    it 'prints error and calls exit when required args missing' do
      allow(Kernel).to receive(:exit)

      expect {
        task_add_raw.invoke(nil, nil, nil)
      }.to output(/ERROR: verbena:mail_queues:add_raw failed/).to_stderr

      expect(Kernel).to have_received(:exit).with(1)
    end

    it 'succeeds with valid file and envelope and prints created id' do
      file = Tempfile.new(['test_raw', '.eml'])
      begin
        file.write("From: example\nTo: to@example.com\n\nHello")
        file.close

        allow_any_instance_of(Verbena::MailQueuesService).to receive(:create_mail_queue_from_file_with_envelope!).and_return(double('MailQueue', id: 123))

        expect {
          task_add_raw.invoke(file.path, 'from@example.com', 'to@example.com')
        }.to output(/Successfully added mail_queue \(123\) with envelope from from@example.com to to@example.com/).to_stdout
      ensure
        file.unlink
      end
    end
  end

  describe 'delete' do
    it 'prints error and calls exit when id missing' do
      allow(Kernel).to receive(:exit)

      expect {
        task_delete.invoke(nil)
      }.to output(/ERROR: verbena:mail_queues:delete failed/).to_stderr

      expect(Kernel).to have_received(:exit).with(1)
    end

    it 'deletes existing mail_queue and prints success message' do
      mq = FactoryBot.create(:mail_queue, token: token)

      expect {
        task_delete.invoke(mq.id.to_s)
      }.to output(/Deleted mail_queue id=#{mq.id}/).to_stdout

      expect(MailQueue.where(id: mq.id)).to be_empty
    end
  end
end
