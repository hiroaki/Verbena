require 'rails_helper'

RSpec.describe 'Timezone configuration' do
  it 'sets application time zone to UTC' do
    expect(Time.zone.name).to eq('UTC')
  end

  it 'sets ActiveRecord default timezone to :utc' do
  expect(ActiveRecord.default_timezone).to eq(:utc)
  end
end
