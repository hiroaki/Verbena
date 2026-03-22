require 'rails_helper'

RSpec.describe Verbena::Settings do
  before do
    described_class.reset!
  end

  describe '.configure with flat keys' do
    it 'applies smtp and pagination settings (with casting via readers)' do
      described_class.configure(
        smtp_address: 'smtp.example.com',
        smtp_port: '587',
        smtp_domain: 'example.com',
        smtp_user_name: 'user',
        smtp_password: 'pass',
        smtp_authentication: 'login',
        smtp_enable_starttls_auto: 'true',
        api_pagination_default_limit: '7',
        api_pagination_limit_cap: '77',
        api_pagination_default_offset: '3',
        file_delivery_dir: '/tmp/mails'
      )

      cfg = described_class.smtp_delivery_config
      expect(cfg[:address]).to eq('smtp.example.com')
      expect(cfg[:port]).to eq(587)
      expect(cfg[:enable_starttls_auto]).to eq(true)

      expect(described_class.api_pagination_default_limit).to eq(7)
      expect(described_class.api_pagination_limit_cap).to eq(77)
      expect(described_class.api_pagination_default_offset).to eq(3)

      expect(described_class.file_delivery_dir).to eq('/tmp/mails')
    end

    it 'falls back to defaults for blank numeric values' do
      described_class.configure(
        api_pagination_default_limit: '',
        api_pagination_default_offset: " \t ",
        delivery_max_retries: '',
        delivery_lock_ttl_seconds: '',
        delivery_lock_max_seconds: ''
      )

      expect(described_class.api_pagination_default_limit).to eq(50)
      expect(described_class.api_pagination_limit_cap).to eq(1000)
      expect(described_class.api_pagination_default_offset).to eq(0)
      expect(described_class.delivery_max_retries).to eq(5)
      expect(described_class.delivery_lock_ttl_seconds).to eq(300)
      expect(described_class.delivery_lock_max_seconds).to eq(3600)
    end

    it 'raises for invalid numeric values' do
      described_class.configure(api_pagination_limit_cap: 'not-a-number')
      expect { described_class.api_pagination_limit_cap }
        .to raise_error(ArgumentError, /VERBENA_API_PAGINATION_LIMIT_CAP/)
    end

    it 'raises for out-of-range numeric values' do
      described_class.configure(delivery_lock_ttl_seconds: '0')
      expect { described_class.delivery_lock_ttl_seconds }
        .to raise_error(ArgumentError, /VERBENA_DELIVERY_LOCK_TTL_SECONDS/)
    end
  end

  describe 'unknown keys' do
    it 'ignores unknown keys without raising and keeps defaults' do
      expect {
        described_class.configure(foo: 'bar', 'not_a_setting' => 'x')
      }.not_to raise_error

      # Defaults remain
      expect(described_class.api_pagination_default_limit).to eq(50)
      expect(described_class.smtp_delivery_config[:address]).to be_nil
    end

    it 'applies known keys while ignoring unknown ones' do
      described_class.configure(smtp_address: 'ok.example', mystery: 'm')
      expect(described_class.smtp_delivery_config[:address]).to eq('ok.example')

      # Unknown key did not create accessors
      expect(described_class.config.respond_to?(:mystery)).to be false
      expect(described_class.config.respond_to?(:mystery=)).to be false
    end
  end
end
