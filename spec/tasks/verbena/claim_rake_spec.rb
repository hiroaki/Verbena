require 'rails_helper'
require 'rake'

RSpec.describe 'verbena:claim tasks' do
  before do
    Rake.application = Rake::Application.new
    load Rails.root.join('lib', 'tasks', 'verbena', 'claim.rake')
    Rake::Task.define_task(:environment)
  end

  let(:task_release_stale) { Rake::Task['verbena:claim:release_stale'] }
  let(:task_show_stale) { Rake::Task['verbena:claim:show_stale'] }

  before do
    task_release_stale.reenable
    task_show_stale.reenable
  end

  describe 'release_stale' do
    it 'prints error and exits when older_than_hours is not numeric' do
      stderr_output = StringIO.new
      expect {
        begin
          $stderr = stderr_output
          task_release_stale.invoke('abc')
        ensure
          $stderr = STDERR
        end
      }.to raise_error(SystemExit) { |ex|
        expect(ex.status).to eq(1)
      }
      expect(stderr_output.string).to match(/ERROR: release_stale failed: .*ArgumentError/)
    end

    it 'prints error and exits when older_than_hours is negative' do
      stderr_output = StringIO.new
      expect {
        begin
          $stderr = stderr_output
          task_release_stale.invoke('-1')
        ensure
          $stderr = STDERR
        end
      }.to raise_error(SystemExit) { |ex|
        expect(ex.status).to eq(1)
      }
      expect(stderr_output.string).to match(/ERROR: release_stale failed: .*NegativeClaimHoursError: older_than_hours must be >= 0/)
    end

    it 'runs dry-run mode and prints summary' do
      service = instance_double(Verbena::MailQueuesService, count_stale_claims: 3)
      allow(Verbena::MailQueuesService).to receive(:new).and_return(service)

      expect {
        task_release_stale.invoke('2', 'true')
      }.to output(/DRY RUN: Would release 3 stale claims older than 2.0 hours/).to_stdout
      expect(service).to have_received(:count_stale_claims).with(older_than_hours: 2.0)
    end

    it 'runs non-dry mode and prints summary' do
      service = instance_double(Verbena::MailQueuesService, release_stale_claims!: 5)
      allow(Verbena::MailQueuesService).to receive(:new).and_return(service)

      expect {
        task_release_stale.invoke('1.5', nil)
      }.to output(/Released 5 stale claims older than 1.5 hours/).to_stdout
      expect(service).to have_received(:release_stale_claims!).with(older_than_hours: 1.5)
    end

    it 'prints error and exits when service raises' do
      service = instance_double(Verbena::MailQueuesService)
      allow(Verbena::MailQueuesService).to receive(:new).and_return(service)
      allow(service).to receive(:release_stale_claims!).and_raise(StandardError, 'boom')

      stderr_output = StringIO.new
      expect {
        begin
          $stderr = stderr_output
          task_release_stale.invoke('1', nil)
        ensure
          $stderr = STDERR
        end
      }.to raise_error(SystemExit) { |ex|
        expect(ex.status).to eq(1)
      }
      expect(stderr_output.string).to match(/ERROR: release_stale failed: StandardError: boom/)
    end
  end

  describe 'show_stale' do
    it 'prints the stale records table' do
      service = instance_double(Verbena::MailQueuesService)
      allow(Verbena::MailQueuesService).to receive(:new).and_return(service)

      claimed_time = Time.utc(2024, 1, 1, 12, 0, 0)
      allow(service).to receive(:show_stale_claims).and_return([
        { id: 1, session_id: 'abcdef123456', claimed_at: claimed_time, envelope_to: 'user@example.com', age_seconds: 3661 }
      ])

      stdout_output = StringIO.new
      begin
        $stdout = stdout_output
        task_show_stale.invoke
      ensure
        $stdout = STDOUT
      end
      expect(stdout_output.string).to match(/Found 1 claimed but undelivered records:/)
      expect(stdout_output.string).to match(/ID\tSession ID\tClaimed At\tEnvelope To\tAge/)
      expect(stdout_output.string).to match(/-+/)
      expect(stdout_output.string).to match(/1\tabcdef123\.\.\.\t#{Regexp.escape(claimed_time.to_s)}\tuser@example.com\t1h1m1s/)
    end

    it 'prints message when no stale records exist' do
      service = instance_double(Verbena::MailQueuesService, show_stale_claims: [])
      allow(Verbena::MailQueuesService).to receive(:new).and_return(service)

      expect {
        task_show_stale.invoke
      }.to output(/No stale claimed records found\./).to_stdout
    end

    it 'prints error and exits when service raises' do
      service = instance_double(Verbena::MailQueuesService)
      allow(Verbena::MailQueuesService).to receive(:new).and_return(service)
      allow(service).to receive(:show_stale_claims).and_raise(StandardError, 'boom')

      stderr_output = StringIO.new
      expect {
        begin
          $stderr = stderr_output
          task_show_stale.invoke
        ensure
          $stderr = STDERR
        end
      }.to raise_error(SystemExit) { |ex|
        expect(ex.status).to eq(1)
      }
      expect(stderr_output.string).to match(/ERROR: show_stale failed: StandardError: boom/)
    end
  end
end