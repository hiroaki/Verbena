require 'rake'
require 'tempfile'
require 'stringio'

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
    it 'errors when eml path is missing' do
      expect {
        capture_output { task_add.invoke(nil) }
      }.to raise_error(SystemExit)
    end

    it 'errors when file not found' do
      expect {
        capture_output { task_add.invoke('/path/does/not/exist.eml') }
      }.to raise_error(SystemExit)
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
    it 'errors when required args missing' do
      expect {
        capture_output { task_add_raw.invoke(nil, nil, nil) }
      }.to raise_error(SystemExit)
    end
  end

  describe 'delete' do
    it 'errors when id missing' do
      expect {
        capture_output { task_delete.invoke(nil) }
      }.to raise_error(SystemExit)
    end
  end
end
