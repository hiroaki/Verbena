require 'rails_helper'

RSpec.describe Verbena::MailQueuesService, type: :service do
  let!(:genzai_jikoku) { Time.zone.parse('2023-10-23 10:11:22') }

  before do
    travel_to genzai_jikoku
  end

  describe 'コンストラクタ' do
    describe do
      it 'インスタンス化できる' do
        expect(described_class.new).to be_a(described_class)
      end
    end
  end

  describe 'インスタンスメソッド' do
    describe '#create_mail_queues_by_eml!' do
      let!(:instance) { described_class.new }

      context '宛先が四件(To:1,Cc:2,Bcc:1)あるメールの場合' do
        let!(:eml) do
          <<-EML1
Date: Tue, 1 Jul 2003 10:52:37 +0200
From: me@example.com
To: you@example.com
Cc: ichiro@example.com, jirou@example.com
Bcc: saburo@example.com
Subject: =?UTF-8?Q?=E3=81=94=E6=8C=A8=E6=8B=B6?=
Content-Type: text/plain; charset="UTF-8"

こんにちは。
          EML1
        end

        # 上述の eml の Date: の値を設定してください
        let!(:header_date) { Time.zone.parse('Tue, 1 Jul 2003 10:52:37 +0200') }

        # WORKAROUND: FIXME: 実装コードに依存したテストです。
        # 都合により EmlSource を先に作って利用しているので、 EmlSource に関するテストはここではできません。
        describe '4件のうち最後の 1件の create で例外が発生した場合' do
          before do
            eml_source = FactoryBot.create(:eml_source)
            return_values = [true, true, true, false]
            allow(eml_source.mail_queues).to receive(:create!).exactly(4).times do
              if return_values.shift
                FactoryBot.create(:mail_queue, eml_source: eml_source)
              else
                raise(ActiveRecord::StatementInvalid)
              end
            end
            allow(EmlSource).to receive(:create!).and_return(eml_source)

            begin
              @result = instance.create_mail_queues_by_eml!(eml)
            rescue
            end
          end

          describe '作成されるレコードについて' do
            it 'mail_queues が 0件 作成される' do
              expect(MailQueue.all.count).to eq 0
            end
          end
        end

        describe '4件のうちで例外が発生しない場合' do
          before do
            @result = instance.create_mail_queues_by_eml!(eml)
          end

          describe '作成されるレコードについて' do
            it 'mail_queues が 4件 作成される' do
              expect(MailQueue.all.count).to eq 4
            end

            it 'eml_sources が 1件 作成される' do
              expect(EmlSource.all.count).to eq 1
            end

            it 'delivery_responses が 0件 作成される' do
              expect(DeliveryResponse.all.count).to eq 0
            end
          end

          describe '作成される mail_queues レコード 4件 について' do
            it 'session_id が、いずれも nil である' do
              expect(MailQueue.all.map {|mq| mq.session_id}).to eq [nil, nil, nil, nil]
            end

            it 'timer_at が、いずれも Date: ヘッダの値の日時 である' do
              expect(MailQueue.all.map {|mq| mq.timer_at}).to eq [header_date, header_date, header_date, header_date]
            end

            it 'envelope_to が EML の宛先の4件をカバーしている' do
              expect(MailQueue.all.map {|mq| mq.envelope_to}).to eq %w(you@example.com ichiro@example.com jirou@example.com saburo@example.com)
            end

            it 'envelope_from が、いずれも me@example.com である' do
              expect(MailQueue.all.map {|mq| mq.envelope_from}).to eq %w(me@example.com me@example.com me@example.com me@example.com)
            end

            it 'eml_source_id が、すべて同一である' do
              expect(MailQueue.all.map {|mq| mq.eml_source_id}.uniq.size).to eq 1
            end
          end

          describe '関連する eml_sources レコード について' do
            it 'eml の内容が 入力メールの全文である' do
              expect(MailQueue.last.eml).to eq eml
            end
          end

          describe '戻り値について' do
            it '4件の MailQueue のインスタンス' do
              expect(@result.map(&:class)).to eq [MailQueue, MailQueue, MailQueue, MailQueue]
            end
            it 'MailQueue のインスタンスの id が、作成されたレコードの id に等しい' do
              expect(@result.map(&:id)).to eq MailQueue.pluck(:id)
            end
          end
        end
      end

      context 'Date: が記述されていないメールの場合' do
        let!(:eml) do
          <<-EML1
From: me@example.com
To: you@example.com
Subject: =?UTF-8?Q?=E3=81=94=E6=8C=A8=E6=8B=B6?=
Content-Type: text/plain; charset="UTF-8"

こんにちは。
          EML1
        end

        describe '例外が発生しない場合' do
          before do
            @result = instance.create_mail_queues_by_eml!(eml)
          end

          it 'timer_at が 現在時刻の日時 である' do
            expect(MailQueue.last.timer_at).to eq genzai_jikoku
          end
        end
      end
    end

    describe '#destroy_mail_queue_by_id!' do
      let!(:instance) { described_class.new }

      context 'mail_queues レコードが 1件 ある場合' do
        let!(:mail_queue) { FactoryBot.create(:mail_queue) }

        context '存在するレコードの id を指定する場合' do
          before do
            instance.destroy_mail_queue_by_id!(mail_queue.id)
          end

          it '指定したレコードが削除される' do
            expect(MailQueue.where(id: mail_queue.id).first).to be nil
          end
        end

        context '存在しないレコードの id を指定する場合' do
          it '例外 ActiveRecord::RecordNotFound が投げられる' do
            expect { instance.destroy_mail_queue_by_id!(mail_queue.id + 1) }.to raise_error(ActiveRecord::RecordNotFound)
          end
        end
      end
    end

    describe '#destroy_mail_queue!' do
      let!(:instance) { described_class.new }

      context 'mail_queues レコードが 1件 ある場合' do
        let!(:mail_queue) { FactoryBot.create(:mail_queue) }

        context '存在するレコード を指定する場合' do
          before do
            instance.destroy_mail_queue!(mail_queue)
          end

          it '指定したレコードが削除される' do
            expect(MailQueue.where(id: mail_queue.id).first).to be nil
          end
        end

        context '存在しないレコード を指定する場合' do
          it '例外 ActiveRecord::RecordNotFound が投げられない' do
            expect { instance.destroy_mail_queue!(FactoryBot.build(:mail_queue)) }.not_to raise_error
          end
        end
      end
    end
  end
end
