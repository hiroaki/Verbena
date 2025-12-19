require 'rails_helper'

RSpec.describe MailQueue, type: :model do
  describe 'timestamp policy during claim' do
    let!(:now) { Time.zone.parse('2023-11-20 12:00:00') }

    before do
      travel_to now
    end

    it 'sets claimed_at consistently within a single claim run and updated_at to a recent time' do
      rows = 3.times.map { FactoryBot.create(:mail_queue, :untouched, timer_at: now - 1.minute) }

      count = described_class.claim_by_timer!('sess-ts')
      expect(count).to eq(rows.size)

      claimed = described_class.claimed('sess-ts').order(:id).to_a
      expect(claimed.size).to eq(rows.size)

      # claimed_at should be the session-consistent timestamp (around `now`)
      claimed.each do |r|
        expect(r.claimed_at).to be_within(1.second).of(now)
        # updated_at is set via Time.current at update time; under travel_to it matches now
        expect(r.updated_at).to be_within(1.second).of(Time.current)
      end
    end
  end
end
