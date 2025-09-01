require 'rails_helper'

RSpec.describe Verbena::JsonLogFormatter do
  it 'renders JSON with base keys for string message' do
    formatter = described_class.new
    time = Time.utc(2025, 1, 2, 3, 4, 5)
    out = formatter.call('INFO', time, nil, 'hello world')
    json = JSON.parse(out)
    expect(json['level']).to eq('info')
    expect(json['timestamp']).to eq(time.iso8601)
    expect(json['message']).to eq('hello world')
  end

  it 'renders JSON and merges hash payload' do
    formatter = described_class.new
    time = Time.utc(2025, 1, 2, 3, 4, 5)
    payload = { event: 'deliver.result', session_id: 'abc', mail_queue_id: 1, message_id: 'm1', smtp_status: '250' }
    out = formatter.call('ERROR', time, nil, payload)
    json = JSON.parse(out)
    expect(json['level']).to eq('error')
    expect(json['timestamp']).to eq(time.iso8601)
    expect(json['event']).to eq('deliver.result')
    expect(json['session_id']).to eq('abc')
    expect(json['mail_queue_id']).to eq(1)
    expect(json['message_id']).to eq('m1')
    expect(json['smtp_status']).to eq('250')
  end
end
