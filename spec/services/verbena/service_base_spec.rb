require 'rails_helper'

RSpec.describe Verbena::ServiceBase, type: :service do
  let(:logger) { Logger.new(IO::NULL) }
  let(:service) { described_class.new(logger: logger) }

  describe '#structured_log_hash' do
    it 'returns a hash with all fields' do
      result = service.structured_log_hash(event: 'test', level: 'info', session_id: 'sid', mail_queue_id: 1, message: 'msg', message_id: 'mid', smtp_status: '250', error: 'err')
      expect(result).to eq({
        'event' => 'test',
        'level' => 'info',
        'session_id' => 'sid',
        'mail_queue_id' => 1,
        'message_id' => 'mid',
        'smtp_status' => '250',
        'error' => 'err',
        'message' => 'msg'
      })
    end
    it 'omits nil fields' do
      result = service.structured_log_hash(event: 'test', level: 'info', session_id: 'sid', mail_queue_id: 1)
      expect(result).to eq({
        'event' => 'test',
        'level' => 'info',
        'session_id' => 'sid',
        'mail_queue_id' => 1
      })
    end
  end

  describe '#structured_log_line' do
    it 'returns a string with all fields' do
      result = service.structured_log_line(event: 'test', level: 'info', session_id: 'sid', mail_queue_id: 1, message: 'msg', message_id: 'mid', smtp_status: '250', error: 'err')
      expect(result).to include('event=test', 'level=info', 'session_id=sid', 'mail_queue_id=1', 'message_id=mid', 'smtp_status=250', 'error=err', 'message=msg')
    end
    it 'omits nil fields' do
      result = service.structured_log_line(event: 'test', level: 'info', session_id: 'sid', mail_queue_id: 1)
      expect(result).to include('event=test', 'level=info', 'session_id=sid', 'mail_queue_id=1')
      expect(result).not_to include('message_id=')
    end
  end

  describe '#structured_log (wrapper)' do
    it 'delegates to hash when json_logging_enabled?' do
      allow(service).to receive(:json_logging_enabled?).and_return(true)
      result = service.structured_log(event: 'test', level: 'info', session_id: 'sid', mail_queue_id: 1, message: 'msg')
      expect(result).to eq(service.structured_log_hash(event: 'test', level: 'info', session_id: 'sid', mail_queue_id: 1, message: 'msg'))
    end
    it 'delegates to line when not json_logging_enabled?' do
      allow(service).to receive(:json_logging_enabled?).and_return(false)
      result = service.structured_log(event: 'test', level: 'info', session_id: 'sid', mail_queue_id: 1, message: 'msg')
      expect(result).to eq(service.structured_log_line(event: 'test', level: 'info', session_id: 'sid', mail_queue_id: 1, message: 'msg'))
    end
  end

  describe '#json_logging_enabled?' do
    it 'returns true if formatter is Verbena::JsonLogFormatter' do
      fake_logger = double('Logger', formatter: Verbena::JsonLogFormatter.new)
      allow(Rails).to receive(:logger).and_return(fake_logger)
      expect(service.json_logging_enabled?).to be true
    end

    it 'returns false if formatter is not Verbena::JsonLogFormatter' do
      fake_logger = double('Logger', formatter: Logger::Formatter.new)
      allow(Rails).to receive(:logger).and_return(fake_logger)
      expect(service.json_logging_enabled?).to be false
    end
  end

  describe '.truthy? / #truthy?' do
    it 'returns true for common truthy values' do
      %w[1 true yes y t on n no].each do |v|
        expect(described_class.truthy?(v)).to be true
        expect(service.truthy?(v)).to be true
      end
    end

    it 'returns false for common falsy values' do
      [nil, '', '0', 'false', 'off', 'f'].each do |v|
        expect(described_class.truthy?(v)).to be false
        expect(service.truthy?(v)).to be false
      end
    end
  end
end
