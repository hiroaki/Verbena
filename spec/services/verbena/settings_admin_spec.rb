require 'rails_helper'

RSpec.describe Verbena::Settings do
  before do
    described_class.reset!
  end

  describe 'admin credential readers' do
    it 'strips values and returns strings' do
      described_class.configure(admin_username: '  alice  ', admin_password: '  s3cr3t  ')
      expect(described_class.admin_username).to eq('alice')
      expect(described_class.admin_password).to eq('s3cr3t')
    end

    it 'returns nil for blank or unset values' do
      described_class.configure(admin_username: '', admin_password: nil)
      expect(described_class.admin_username).to be_nil
      expect(described_class.admin_password).to be_nil
    end

    it 'returns nil for whitespace-only values' do
      described_class.configure(admin_username: '   ', admin_password: "\t\n")
      expect(described_class.admin_username).to be_nil
      expect(described_class.admin_password).to be_nil
    end
  end
end
