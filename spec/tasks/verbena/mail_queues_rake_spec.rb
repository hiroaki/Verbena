require 'rails_helper'

RSpec.describe 'verbena:mail_queues tasks' do
  def capture_output
    old_stdout = $stdout
    old_stderr = $stderr
    $stdout = StringIO.new
    $stderr = StringIO.new
    yield
  ensure
    $stdout = old_stdout
    $stderr = old_stderr
  end
  before(:all) do
    Rake.application = Rake::Application.new
    load Rails.root.join('lib/tasks/verbena/mail_queues.rake')
    Rake::Task.define_task(:environment)
  end

  let(:task_add) { Rake::Task['verbena:mail_queues:add'] }
  let(:task_add_raw) { Rake::Task['verbena:mail_queues:add_raw'] }
  let(:task_delete) { Rake::Task['verbena:mail_queues:delete'] }

  before do
    task_add.reenable
    task_add_raw.reenable
    task_delete.reenable
  end

  describe 'add' do
    it 'prints error and calls exit when eml path is missing' do
      allow(Kernel).to receive(:exit)

      expect {
        task_add.invoke(nil)
      }.to output(/ERROR: add failed/).to_stderr

      expect(Kernel).to have_received(:exit).with(1)
    end

    it 'prints error and calls exit when file not found' do
      allow(Kernel).to receive(:exit)

      expect {
        task_add.invoke('/path/does/not/exist.eml')
      }.to output(/ERROR: add failed/).to_stderr

      expect(Kernel).to have_received(:exit).with(1)
    end

    it 'succeeds with a valid file' do
      file = Tempfile.new(['test', '.eml'])
      begin
        file.write("From: example\n\nHello")
        file.close

        allow_any_instance_of(Verbena::MailQueuesService).to receive(:create_mail_queues_from_file!).and_return([1])

        expect {
          capture_output { task_add.invoke(file.path) }
        }.not_to raise_error
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
      }.to output(/ERROR: add_raw failed/).to_stderr

      expect(Kernel).to have_received(:exit).with(1)
    end
  end

  describe 'delete' do
    it 'prints error and calls exit when id missing' do
      allow(Kernel).to receive(:exit)

      expect {
        task_delete.invoke(nil)
      }.to output(/ERROR: delete failed/).to_stderr

      expect(Kernel).to have_received(:exit).with(1)
    end
  end
end
