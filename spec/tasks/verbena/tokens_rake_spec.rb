require 'rails_helper'
require 'rake'

RSpec.describe 'verbena:tokens tasks' do
  before do
    Rake.application = Rake::Application.new
    load Rails.root.join('lib', 'tasks', 'verbena', 'tokens.rake')
    Rake::Task.define_task(:environment)
  end

  let(:task_revoke) { Rake::Task['verbena:tokens:revoke_expired'] }

  before do
    task_revoke.reenable
  end

  describe 'revoke_expired' do
    it 'prints dry run summary when dry flag is truthy' do
      service_double = instance_double(Verbena::TokenService, expired_count: 7)
      allow(Verbena::TokenService).to receive(:new).and_return(service_double)

      expect {
        task_revoke.invoke('1')
      }.to output(/Dry run: 7 tokens would be revoked/).to_stdout
    end

    it 'prints revoked count on success' do
      service_double = instance_double(Verbena::TokenService, revoke_expired!: 3)
      allow(Verbena::TokenService).to receive(:new).and_return(service_double)

      expect {
        task_revoke.invoke(nil)
      }.to output(/Revoked 3 tokens/).to_stdout
    end

    it 'prints error and calls exit on service error' do
      allow(Kernel).to receive(:exit)
      service_double = instance_double(Verbena::TokenService)
      allow(service_double).to receive(:revoke_expired!).and_raise('boom')
      allow(Verbena::TokenService).to receive(:new).and_return(service_double)

      expect {
        task_revoke.invoke(nil)
      }.to output(/ERROR: revoke_expired failed/).to_stderr

      expect(Kernel).to have_received(:exit).with(1)
    end
  end
end
