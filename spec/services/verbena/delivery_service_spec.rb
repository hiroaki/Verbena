require 'rails_helper'

# WORKAROUND: FIXME:
# 以下のテストの中で、 Mail::Message の delivery_method に次のクラスを使用している点について：
# - Mail::TestMailer
# - TestMailerRespondOk
# - TestMailerRespondNg
# - TestMailerRespondOkButTooLong
# （クラスの定義は rails_helper 内に書いています）
# アプリは VERBENA_DELIVERY_METHOD により配送方式を切替可能です。
# ただしテストで ENV を直接変更しない方針とし、
# Verbena::Settings.delivery_method をモックして挙動を制御します。
# また Mail の内部実装に依存しないよう、必要に応じて DeliveryService#send_mail! をスタブし、
# Mail::Message と Net::SMTP::Response（成功/失敗/長文）を明示的に渡して検証します。

RSpec.describe Verbena::DeliveryService, type: :service do
  let!(:genzai_jikoku) { Time.zone.parse('2023-10-23 10:11:22') }

  before do
    travel_to genzai_jikoku
    # Ensure test delivery method regardless of container env, without mutating ENV
  allow(Verbena::Settings).to receive(:delivery_method).and_return(:test)
  end

  describe 'コンストラクタ' do
    describe '引数に関して' do
      context 'オプションを渡さない場合' do
        it 'インスタンス化できる' do
          expect(described_class.new).to be_a(described_class)
        end
      end

      context 'オプションに { job_id: "job1" } を渡す場合' do
        let!(:opts) { { job_id: "job1" } }

        it 'インスタンス化できる' do
          expect(described_class.new(opts)).to be_a described_class
        end
      end
    end

    describe '作成したインスタンスの @job_id に関して' do
      context 'コンストラクタに { job_id: "job1" } を渡す場合' do
        let!(:opts) { { job_id: "job1" } }
        it '"job1" が設定される' do
          expect(described_class.new(opts).job_id).to eq 'job1'
        end
      end

      context 'コンストラクタに引数を渡さない場合' do
        it 'nilになる' do
          expect(described_class.new.job_id).to be_nil
        end
      end
    end
  end

  describe 'インスタンスメソッド' do












    describe '#perform_one' do
      let!(:instance) { described_class.new }
      let!(:eml_source) do
        FactoryBot.create(:eml_source, eml: <<-EML)
Date: Sat, 11 Nov 2023 09:09:49 +0000 (GMT)
From: from.address@example.jp
To: to1.address@example.com
Subject: Greeting

Hello World!
        EML
      end
      let!(:mail_queue) { FactoryBot.create(:mail_queue, :untouched, eml_source: eml_source) }

      describe '#send_mail! について' do
        context do
          it '１回実行される' do
            expect(instance).to receive(:send_mail!).once
            instance.perform_one(mail_queue)
          end
        end
      end

      describe 'DeliveryResponse について' do
        context '送信の結果、成功のレスポンスを得た場合' do
          before do
            allow(instance).to receive(:send_mail!) do |mq, &blk|
              message = Mail.read_from_string(mq.eml)
              message.delivery_method(Mail::TestMailer)
              Mail::TestMailer.deliveries << message
              response = Net::SMTP::Response.parse('250 dummy reply code')
              blk.call(message, response)
            end
            instance.perform_one(mail_queue)
            mail_queue.reload
          end

          it 'ステータス 250 で保存されている' do
            expect(mail_queue.delivery_responses.order(:created_at).last.status).to eq '250'
          end
        end

        context '送信の結果、成功のレスポンスを得た場合（ただし含まれるメッセージ長がカラムサイズを超えているケース）' do
          before do
            allow(instance).to receive(:send_mail!) do |mq, &blk|
              message = Mail.read_from_string(mq.eml)
              message.delivery_method(Mail::TestMailer)
              Mail::TestMailer.deliveries << message
              response = Net::SMTP::Response.parse("250 too long message Ax256=>#{'A'*256}")
              blk.call(message, response)
            end
            instance.perform_one(mail_queue)
            mail_queue.reload
          end

          it 'ステータス 250 で保存されている' do
            expect(mail_queue.delivery_responses.order(:created_at).last.status).to eq '250'
          end
        end

        context '送信の結果、成功ではないレスポンスを得た場合' do
          before do
            allow(instance).to receive(:send_mail!) do |mq, &blk|
              message = Mail.read_from_string(mq.eml)
              message.delivery_method(Mail::TestMailer)
              Mail::TestMailer.deliveries << message
              response = Net::SMTP::Response.parse('400 dummy reply code')
              blk.call(message, response)
            end
          end

          it 'ステータス 250 以外で保存され、例外が発生する' do
            expect {
              instance.perform_one(mail_queue)
            }.to raise_error(Net::SMTPServerBusy)
            mail_queue.reload
            expect(mail_queue.delivery_responses.order(:created_at).last.status).not_to eq '250'
          end
        end
      end

      describe 'ログについて' do
        context '送信の結果、成功のレスポンスを得た場合' do
          before do
            allow(instance).to receive(:send_mail!) do |mq, &blk|
              message = Mail.read_from_string(mq.eml)
              message.delivery_method(Mail::TestMailer)
              Mail::TestMailer.deliveries << message
              response = Net::SMTP::Response.parse('250 ok')
              blk.call(message, response)
            end
          end

          it '送信成功した info ログと、 DeliveryResponse を作成した info ログが記録される' do
            expect(instance.logger).to receive(:info).with(include("event=deliver.result", "level=info", "mail_queue_id=#{mail_queue.id}", "message=OK sending a message mail_queues.id=[#{mail_queue.id}]"))
            expect(instance.logger).to receive(:info).with(/CREATED DeliveryResponse/)
            instance.perform_one(mail_queue)
          end
        end

        context '送信の結果、成功ではないレスポンスを得た場合' do
          before do
            allow(instance).to receive(:send_mail!) do |mq, &blk|
              message = Mail.read_from_string(mq.eml)
              message.delivery_method(Mail::TestMailer)
              Mail::TestMailer.deliveries << message
              response = Net::SMTP::Response.parse('400 ng')
              blk.call(message, response)
            end
          end

          it '送信失敗した error ログと、 DeliveryResponse を作成した info ログが記録され、例外が発生する' do
            expect(instance.logger).to receive(:error).with(include("event=deliver.result", "level=error", "mail_queue_id=#{mail_queue.id}", "message=NG (Retryable) sending a message mail_queues.id=[#{mail_queue.id}]"))
            expect(instance.logger).to receive(:info).with(/CREATED DeliveryResponse/)
            expect {
              instance.perform_one(mail_queue)
            }.to raise_error(Net::SMTPServerBusy)
          end
        end

        context '送信が失敗（例外が投げられた）場合' do
          before do
            allow(instance).to receive(:send_mail!).and_raise(StandardError, 'foo bar baz')
          end

          it '例外メッセージを含んだ error ログと、 DeliveryResponse を作成した info ログが記録される' do
            expect(instance.logger).to receive(:error).with(/event=deliver\.(result|exception).*level=error.*mail_queue_id=#{mail_queue.id}.*foo bar baz/)
            expect(instance.logger).to receive(:info).with(/CREATED DeliveryResponse/)
            instance.perform_one(mail_queue)
          end
        end
      end
    end

    describe '#send_mail!' do
      let!(:instance) { described_class.new }
      let!(:eml_source) do
        FactoryBot.create(:eml_source, eml: <<-EML)
Date: Sat, 11 Nov 2023 09:09:49 +0000 (GMT)
From: from.address@example.jp
To: to1.address@example.com
Subject: Greeting

Hello World!
        EML
      end

      before do
        Mail::TestMailer.deliveries.clear
        instance.send_mail!(mail_queue)
      end

      describe '送信される件数について' do
        let!(:mail_queue) { FactoryBot.create(:mail_queue, eml_source: eml_source) }
        it '1件である' do
          expect(Mail::TestMailer.deliveries.count).to eq 1
        end
      end

      describe '送信される 1件 について' do
        before do
          @deliveried = Mail::TestMailer.deliveries.last
        end

        describe 'メール・ヘッダ Subject について' do
          let!(:mail_queue) { FactoryBot.create(:mail_queue, eml_source: eml_source) }
          it {
            expect(@deliveried.subject).to eq 'Greeting'
          }
        end

        describe 'メール・ヘッダ To について' do
          let!(:mail_queue) { FactoryBot.create(:mail_queue, eml_source: eml_source) }
          it {
            expect(@deliveried.to).to eq ['to1.address@example.com']
          }
        end

        describe 'メール・ヘッダ From について' do
          let!(:mail_queue) { FactoryBot.create(:mail_queue, eml_source: eml_source) }
          it {
            expect(@deliveried.from).to eq ['from.address@example.jp']
          }
        end

        describe 'エンベロープ From について' do
          let!(:mail_queue) { FactoryBot.create(:mail_queue, eml_source: eml_source, envelope_from: 'me') }
          it {
            expect(@deliveried.smtp_envelope_from).to eq 'me'
          }
        end

        describe 'エンベロープ To について' do
          let!(:mail_queue) { FactoryBot.create(:mail_queue, eml_source: eml_source, envelope_to: 'you') }
          it {
            expect(@deliveried.smtp_envelope_to).to eq ['you']
          }
        end

        describe 'メール本文について' do
          let!(:mail_queue) { FactoryBot.create(:mail_queue, eml_source: eml_source) }
          it {
            expect(@deliveried.body.to_s).to eq "Hello World!\n"
          }
        end
      end
    end
  end
end
