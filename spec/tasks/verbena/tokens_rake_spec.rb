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
      allow_any_instance_of(Verbena::TokenService).to receive(:expired_count).and_return(7)

      expect {
        task_revoke.invoke('1')
      }.to output(/Dry run: 7 tokens would be revoked/).to_stdout
    end

    it 'prints revoked count on success' do
      allow_any_instance_of(Verbena::TokenService).to receive(:revoke_expired!).and_return(3)

      expect {
        task_revoke.invoke(nil)
      }.to output(/Revoked 3 tokens/).to_stdout
    end

    it 'prints error and calls exit on service error' do
      allow(Kernel).to receive(:exit)
      allow_any_instance_of(Verbena::TokenService).to receive(:revoke_expired).and_raise('boom')

      expect {
        task_revoke.invoke(nil)
      }.to output(/ERROR: revoke_expired failed/).to_stderr

      expect(Kernel).to have_received(:exit).with(1)
    end
  end
end
