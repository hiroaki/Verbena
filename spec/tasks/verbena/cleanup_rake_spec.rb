require 'rails_helper'
require 'rake'

RSpec.describe 'verbena:cleanup tasks' do
  before do
    Rake.application = Rake::Application.new
    load Rails.root.join('lib', 'tasks', 'verbena', 'cleanup.rake')
    Rake::Task.define_task(:environment)
  end

  let(:task_monthly) { Rake::Task['verbena:cleanup:monthly'] }
  let(:task_weekly)  { Rake::Task['verbena:cleanup:weekly'] }
  let(:task_daily)   { Rake::Task['verbena:cleanup:daily'] }
  let(:task_now)     { Rake::Task['verbena:cleanup:now'] }
  let(:task_by_ttl)  { Rake::Task['verbena:cleanup:by_ttl'] }

  before do
    task_monthly.reenable
    task_weekly.reenable
    task_daily.reenable
    task_now.reenable
    task_by_ttl.reenable
  end

  shared_examples 'cleanup error handling' do |task|
    it 'prints error and calls exit when service raises' do
      allow(Kernel).to receive(:exit)
      allow_any_instance_of(Verbena::CleanupService).to receive(:cleanup).and_raise(StandardError, 'test error')

      expect {
        send(task).invoke
      }.to output(/ERROR: .* failed: StandardError: test error/).to_stderr

      expect(Kernel).to have_received(:exit).with(1)
    end
  end

  describe 'monthly' do
    include_examples 'cleanup error handling', :task_monthly
    it 'prints result on success' do
      allow_any_instance_of(Verbena::CleanupService).to receive(:cleanup).and_return({ mail_queues: 2, eml_sources: 1 })
      expect {
        task_monthly.invoke
      }.to output(/mail_queues=2 eml_sources=1/).to_stdout
    end
  end

  describe 'weekly' do
    include_examples 'cleanup error handling', :task_weekly
    it 'prints result on success' do
      allow_any_instance_of(Verbena::CleanupService).to receive(:cleanup).and_return({ mail_queues: 3, eml_sources: 0 })
      expect {
        task_weekly.invoke
      }.to output(/mail_queues=3 eml_sources=0/).to_stdout
    end
  end

  describe 'daily' do
    include_examples 'cleanup error handling', :task_daily
    it 'prints result on success' do
      allow_any_instance_of(Verbena::CleanupService).to receive(:cleanup).and_return({ mail_queues: 1, eml_sources: 2 })
      expect {
        task_daily.invoke
      }.to output(/mail_queues=1 eml_sources=2/).to_stdout
    end
  end

  describe 'now' do
    include_examples 'cleanup error handling', :task_now
    it 'prints result on success' do
      allow_any_instance_of(Verbena::CleanupService).to receive(:cleanup).and_return({ mail_queues: 5, eml_sources: 4 })
      expect {
        task_now.invoke
      }.to output(/mail_queues=5 eml_sources=4/).to_stdout
    end
  end

  describe 'by_ttl' do
    include_examples 'cleanup error handling', :task_by_ttl
    it 'prints result on success' do
      allow_any_instance_of(Verbena::CleanupService).to receive(:cleanup).and_return({ mail_queues: 7, eml_sources: 8 })
      expect {
        task_by_ttl.invoke
      }.to output(/mail_queues=7 eml_sources=8/).to_stdout
    end
  end
end
