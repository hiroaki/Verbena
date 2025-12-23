require 'rails_helper'

RSpec.describe 'Timezone configuration' do
  it 'sets application time zone to UTC' do
    expect(Time.zone.name).to eq('UTC')
  end

  it 'sets ActiveRecord default timezone to :utc' do
    expect(ActiveRecord.default_timezone).to eq(:utc)
  end

  it 'uses UTC for DB session timezone when using MySQL/MariaDB' do
    adapter = ActiveRecord::Base.connection.adapter_name.downcase
    skip "non-MySQL adapter: #{adapter}" unless adapter.include?('mysql')

    diff_seconds = ActiveRecord::Base.connection.select_value(
      "SELECT TIMESTAMPDIFF(SECOND, UTC_TIMESTAMP(), NOW())"
    ).to_i

    expect(diff_seconds).to eq(0)
  end
end
