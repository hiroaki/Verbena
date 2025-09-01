require 'rails_helper'

RSpec.describe DeliveryResponse, type: :model do
  describe 'コンストラクタ' do
    it 'インスタンス化できる' do
      expect(FactoryBot.build(:delivery_response).class).to eq described_class
    end
  end

  describe 'クラスメソッド' do
    describe '#last_status_4xx_within_time_limit' do
      let!(:current_time) { Time.zone.parse('2023-08-10 10:00:00 +0900') }

      before do
        travel_to current_time
      end

      context 'メールキュー 1, 2, 3, 4 がある場合' do
        let!(:mq1) { FactoryBot.create(:mail_queue) }
        let!(:mq2) { FactoryBot.create(:mail_queue) }
        let!(:mq3) { FactoryBot.create(:mail_queue) }
        let!(:mq4) { FactoryBot.create(:mail_queue) }

        shared_context 'メールキュー 1 のレスポンスが 2 つ = 6 時間前、 3 時間前の順にステータス [400, 400] である場合' do
          let!(:dr1a) { FactoryBot.create(:delivery_response, mail_queue: mq1, status: '400', responded_at: current_time - 6.hours) }
          let!(:dr1b) { FactoryBot.create(:delivery_response, mail_queue: mq1, status: '400', responded_at: current_time - 3.hours) }
        end

        shared_context 'メールキュー 2 のレスポンスが 1 つ = 3 時間前のものがステータス [250] である場合' do
          let!(:dr2a) { FactoryBot.create(:delivery_response, mail_queue: mq2, status: '250', responded_at: current_time - 3.hours) }
        end

        shared_context 'メールキュー 3 のレスポンスが 3 つ = 9 時間前、 6 時間前、 3時間前の順にステータス [400, 400, 400] である場合' do
          let!(:dr3a) { FactoryBot.create(:delivery_response, mail_queue: mq3, status: '400', responded_at: current_time - 9.hours) }
          let!(:dr3b) { FactoryBot.create(:delivery_response, mail_queue: mq3, status: '400', responded_at: current_time - 6.hours) }
          let!(:dr3c) { FactoryBot.create(:delivery_response, mail_queue: mq3, status: '400', responded_at: current_time - 3.hours) }
        end

        shared_context 'メールキュー 4 のレスポンスが 2 つ = 9 時間前、 6 時間前の順にステータス [400, 250] である場合' do
          let!(:dr4a) { FactoryBot.create(:delivery_response, mail_queue: mq4, status: '400', responded_at: current_time - 9.hours) }
          let!(:dr4b) { FactoryBot.create(:delivery_response, mail_queue: mq4, status: '250', responded_at: current_time - 6.hours) }
        end

        subject { DeliveryResponse.last_status_4xx_within_time_limit(timelimit).map(&:id) }

        describe '制限時間を度外視したときに選択されるべきレコードについて' do
          context 'メールキュー 1, 3 の最新のレスポンスのステータスが 400 であり、メールキュー 2, 4 の最新のレスポンスが 250 である場合' do
            include_context 'メールキュー 1 のレスポンスが 2 つ = 6 時間前、 3 時間前の順にステータス [400, 400] である場合'
            include_context 'メールキュー 2 のレスポンスが 1 つ = 3 時間前のものがステータス [250] である場合'
            include_context 'メールキュー 3 のレスポンスが 3 つ = 9 時間前、 6 時間前、 3時間前の順にステータス [400, 400, 400] である場合'
            include_context 'メールキュー 4 のレスポンスが 2 つ = 9 時間前、 6 時間前の順にステータス [400, 250] である場合'

            context 'パラメータに、すべての配送レスポンスのうちで最古の時刻が含まれる値を渡す場合' do
              let!(:timelimit) { '72:00:00' }

              it 'メールキュー 1 と 3 それぞれの、最新のレスポンスのレコードだけのリストが得られる' do
                is_expected.to eq [dr1b.id, dr3c.id]
              end
            end
          end
        end

        describe '制限時間がかかる場合について' do
          context 'メールキュー 1 の最新のレスポンスのステータスが 400 であり、最古のレスポンスの responded_at が {現在時刻 - 6時間} である場合' do
            include_context 'メールキュー 1 のレスポンスが 2 つ = 6 時間前、 3 時間前の順にステータス [400, 400] である場合'

            context 'パラメータに 05:59:00 を渡す場合' do
              let!(:timelimit) { '05:59:00' }

              it '空のリストが得られる' do
                is_expected.to be_empty
              end
            end

            context 'パラメータに 06:00:00 を渡す場合' do
              let!(:timelimit) { '06:00:00' }

              it '空のリストが得られる' do
                is_expected.to be_empty
              end
            end

            context 'パラメータに 06:00:01 を渡す場合' do
              let!(:timelimit) { '06:00:01' }

              it 'メールキュー 1 の最新のレスポンスのレコードだけのリストが得られる' do
                is_expected.to eq [dr1b.id]
              end
            end
          end
        end
      end
    end
  end
end
