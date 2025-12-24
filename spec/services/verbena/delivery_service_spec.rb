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

      context 'オプションに { session_id: "sess" } を渡す場合' do
        let!(:opts) { { session_id: "sess" } }

        context 'mail_queues に session_id が sess のレコードが存在する場合' do
          before do
            FactoryBot.create(:mail_queue, session_id: 'sess')
          end

          it 'インスタンス化できる' do
            expect(described_class.new(opts)).to be_a described_class
          end
        end

        context 'mail_queues に session_id が sess のレコードが存在しない場合' do
          xit 'インスタンス化できない' do
            # 予定では例外にしますが、まだ実装していません
            expect { described_class.new(opts) }.to raise_error(StandardError)
          end
        end
      end
    end

    describe '作成したインスタンスの @session_id に関して' do
      context 'コンストラクタに { session_id: "sess" } を渡す場合' do
        let!(:opts) { { session_id: "sess" } }
        context 'mail_queues に session_id が sess のレコードが存在する場合' do
          before do
            FactoryBot.create(:mail_queue, session_id: 'sess')
          end
          it '"sess" が設定される' do
            expect(described_class.new(opts).session_id).to eq 'sess'
          end
        end
      end

      context 'コンストラクタに引数を渡さない場合' do
        it '少なくとも連続1000回の試行では、重複しない値になる' do
          buf = []
          1.upto(1000) { buf << described_class.new.session_id }
          expect(buf.uniq.length).to eq 1000
        end
      end
    end
  end

  describe 'クラスメソッド' do
    describe '.issue_session_id' do
      it '少なくとも連続1000回の試行では、重複しない値を返す' do
        buf = []
        1.upto(1000) { buf << described_class.issue_session_id }
        expect(buf.uniq.length).to eq 1000
      end
    end
  end

  describe 'インスタンスメソッド' do
    describe '#perform_by_timer' do
      let!(:instance) { described_class.new }

      context '未処理のレコード(timer_at が過去 2件 未来 1件) 、処理済みのレコード(timer_at が過去 1件) がある場合' do
        let!(:mq1) { FactoryBot.create(:mail_queue, :untouched, timer_at: genzai_jikoku - 1.hour) }
        let!(:mq2) { FactoryBot.create(:mail_queue, :untouched, timer_at: genzai_jikoku + 1.hour) }
        let!(:mq3) { FactoryBot.create(:mail_queue, :touched,   timer_at: genzai_jikoku - 1.hour) }
        let!(:mq4) { FactoryBot.create(:mail_queue, :untouched, timer_at: genzai_jikoku - 1.hour) }

        describe '影響を受けるレコード数について' do
          before do
            instance.perform_by_timer
          end

          it '2件 が対象になる' do
            expect(MailQueue.where(session_id: instance.session_id).count).to eq 2
          end

          it '2件の delivery_responses レコードがあり、処理対象の mail_queues の id を示している' do
            expect(DeliveryResponse.all.count).to eq 2
            expect(DeliveryResponse.all.pluck(:mail_queue_id)).to eq [mq1.id, mq4.id]
          end
        end
      end
    end

    describe '#perform_by_mail_queue_id' do
      let!(:instance) { described_class.new }

      context '未処理のレコード(timer_at が過去 2件 未来 1件) 、処理済みのレコード(timer_at が過去 1件) がある場合' do
        let!(:mq1) { FactoryBot.create(:mail_queue, :untouched, timer_at: genzai_jikoku - 1.hour) }
        let!(:mq2) { FactoryBot.create(:mail_queue, :untouched, timer_at: genzai_jikoku + 1.hour) }
        let!(:mq3) { FactoryBot.create(:mail_queue, :touched,   timer_at: genzai_jikoku - 1.hour) }
        let!(:mq4) { FactoryBot.create(:mail_queue, :untouched, timer_at: genzai_jikoku - 1.hour) }

        describe '影響を受けるレコード数について' do
          before do
            instance.perform_by_mail_queue_id(mail_queue_id)
          end

          context '未処理のレコード、 timer_at が過去のレコードを指定する場合' do
            let!(:mail_queue_id) { mq1.id }

            it '1件 が対象になる' do
              expect(MailQueue.where(session_id: instance.session_id).count).to eq 1
            end

            it '1件の delivery_responses レコードがあり、処理対象の mail_queues の id を示している' do
              expect(DeliveryResponse.all.count).to eq 1
              expect(DeliveryResponse.all.pluck(:mail_queue_id)).to eq [mq1.id]
            end
          end

          context '未処理のレコード、 timer_at が未来のレコードを指定する場合' do
            let!(:mail_queue_id) { mq2.id }

            it '1件 が対象になる' do
              expect(MailQueue.where(session_id: instance.session_id).count).to eq 1
            end

            it '1件の delivery_responses レコードがあり、処理対象の mail_queues の id を示している' do
              expect(DeliveryResponse.all.count).to eq 1
              expect(DeliveryResponse.all.pluck(:mail_queue_id)).to eq [mq2.id]
            end
          end

          context '処理済みレコード、 timer_at が過去のレコードを指定する場合' do
            let!(:mail_queue_id) { mq3.id }

            it '0件 が対象になる' do
              expect(MailQueue.where(session_id: instance.session_id).count).to eq 0
            end

            it '0件の delivery_responses レコードがある' do
              expect(DeliveryResponse.all.count).to eq 0
            end
          end
        end
      end
    end

    describe '#prepare_to_retry_for_session' do
      let!(:instance) { described_class.new }

      context do
        let!(:mq1) { FactoryBot.create(:mail_queue, :touched) }
        let!(:mq2) { FactoryBot.create(:mail_queue, :touched) }
        let!(:mq3) { FactoryBot.create(:mail_queue, :touched) }
        let!(:mq4) { FactoryBot.create(:mail_queue, :touched) }

        context do
          before do
            FactoryBot.create(:delivery_response, mail_queue_id: mq1.id, responded_at: genzai_jikoku - 2.hour, status: '400')
            FactoryBot.create(:delivery_response, mail_queue_id: mq2.id, responded_at: genzai_jikoku - 3.hour, status: '400')
            FactoryBot.create(:delivery_response, mail_queue_id: mq2.id, responded_at: genzai_jikoku - 2.hour, status: '250')
            FactoryBot.create(:delivery_response, mail_queue_id: mq3.id, responded_at: genzai_jikoku - 2.hour, status: '250')
            FactoryBot.create(:delivery_response, mail_queue_id: mq4.id, responded_at: genzai_jikoku - 4.hour, status: '400')
          end

          context '引数 time_limit を省略する場合' do
            it '最新のレスポンスがエラーであり、かつそれから 72 時間を経過していないレコードの ID を引数に #reset_mail_queues が呼ばれる' do
              expect(instance).to receive(:reset_mail_queues).with([mq1.id, mq4.id])
              instance.prepare_to_retry_for_session
            end
          end

          context '引数 time_limit に 3 時間の値を渡す場合' do
            it '最新のレスポンスがエラーであり、かつそれから 3 時間を経過していないレコードの ID を引数に #reset_mail_queues が呼ばれる' do
              expect(instance).to receive(:reset_mail_queues).with([mq1.id])
              instance.prepare_to_retry_for_session('03:00:00')
            end
          end

          context '引数 time_limit に不正な形式を渡す場合' do
            it 'ArgumentError を投げる' do
              expect { instance.prepare_to_retry_for_session('DROP TABLE delivery_responses;') }.to raise_error(ArgumentError)
            end
          end

          context '引数 time_limit に 00:00:00 を渡す場合' do
            it 'ArgumentError を投げる' do
              expect { instance.prepare_to_retry_for_session('00:00:00') }.to raise_error(ArgumentError)
            end
          end
        end
      end
    end

    describe '#prepare_to_retry_undelivered' do
      let!(:instance) { described_class.new(session_id: target_session_id) }

      context 'session_id が "something" の MailQueue レコードがある場合' do
        let!(:mq) { FactoryBot.create(:mail_queue, session_id: 'something') }

        context 'その配送結果が存在しない場合' do
          # 再送したいレコードの session_id が nil に変化する（＝再処理可能な状態にリセットされる）ことのテスト
          context 'インスタンス作成時に session_id = "something" を指定する場合' do
            let!(:target_session_id) { 'something' }

            before do
              instance.prepare_to_retry_undelivered
              mq.reload
            end

            it 'MailQueue レコードの session_id が nil である' do
              expect(mq.session_id).to be_nil
            end
          end

          # インスタンスに指定する session_id 以外には影響がおよばないことのテスト
          context 'インスタンス作成時に session_id = "other-string" を指定する場合' do
            let!(:target_session_id) { 'other-string' }

            before do
              instance.prepare_to_retry_undelivered
              mq.reload
            end

            it 'MailQueue レコードの session_id が "something" のままである' do
              expect(mq.session_id).to eq 'something'
            end
          end
        end

        context 'その配送結果が存在する場合' do
          before do
            mq.delivery_responses.create!
          end

          # 処理結果が存在するレコードには影響がおよばないことのテスト
          context 'インスタンス作成時に session_id = "something" を指定する場合' do
            let!(:target_session_id) { 'something' }

            before do
              instance.prepare_to_retry_undelivered
              mq.reload
            end

            it 'MailQueue レコードの session_id が "something" のままである' do
              expect(mq.session_id).to eq 'something'
            end
          end
        end
      end

      # 複数のレコードが影響されることのテスト
      context '状態の異なるいくつかの MailQueue レコードがある場合' do
        let!(:session_id) { 'something' }
        let!(:other_session_id) { 'nothing' }
        let!(:mq1) { FactoryBot.create(:mail_queue, session_id: session_id) }
        let!(:mq2) { FactoryBot.create(:mail_queue, session_id: other_session_id) }
        let!(:mq3) { FactoryBot.create(:mail_queue, session_id: nil) }
        let!(:mq4) { FactoryBot.create(:mail_queue, session_id: session_id) }

        context 'インスタンス作成時に session_id = "something" を指定する場合' do
          let!(:target_session_id) { session_id }

          context '配送結果がどのレコードにも存在しない場合' do
            before do
              instance.prepare_to_retry_undelivered
            end

            it 'インスタンスに指定された session_id の MailQueue レコードの session_id が nil になる' do
              expect(mq1.reload.session_id).to be_nil # <--
              expect(mq2.reload.session_id).not_to be_nil
              expect(mq3.reload.session_id).to be_nil
              expect(mq4.reload.session_id).to be_nil # <--
            end
          end

          context 'ふたつの session_id = something のレコードのひとつだけに配送結果が存在する場合' do
            before do
              mq1.delivery_responses.create!
              instance.prepare_to_retry_undelivered
            end

            it '配送結果の存在するレコードの session_id は変化せず、存在しないレコードの session_id は nil になる' do
              expect(mq1.reload.session_id).to eq session_id
              expect(mq2.reload.session_id).not_to be_nil
              expect(mq3.reload.session_id).to be_nil
              expect(mq4.reload.session_id).to be_nil
            end
          end

          context 'ふたつの session_id = something のレコードそれぞれ配送結果が存在する場合' do
            before do
              mq1.delivery_responses.create!
              mq4.delivery_responses.create!
              instance.prepare_to_retry_undelivered
            end

            it 'それぞれレコードの session_id は変化しない' do
              expect(mq1.reload.session_id).to eq session_id
              expect(mq2.reload.session_id).not_to be_nil
              expect(mq3.reload.session_id).to be_nil
              expect(mq4.reload.session_id).to eq session_id
            end
          end
        end
      end
    end

    describe '#reset_mail_queues' do
      let!(:instance) { described_class.new(session_id: instance_session_id) }

      context 'session_id が同一のレコードが 4件 ある場合' do
        let!(:abcdefg) { 'abcdefg' }
        let!(:mq1) { FactoryBot.create(:mail_queue, session_id: abcdefg) }
        let!(:mq2) { FactoryBot.create(:mail_queue, session_id: abcdefg) }
        let!(:mq3) { FactoryBot.create(:mail_queue, session_id: abcdefg) }
        let!(:mq4) { FactoryBot.create(:mail_queue, session_id: abcdefg) }

        before do
          instance.reset_mail_queues(mail_queue_ids)
        end

        context '引数に、そのうちの 2件 のレコードの id を渡す場合' do
          let!(:mail_queue_ids) { [mq1.id, mq3.id] }

          context 'インスタンスの session_id が、それらレコードの session_id と同一の場合' do
            let!(:instance_session_id) { abcdefg }

            it '指定した 2件 のレコードは "未処理" 状態になる（ほかの 2件 は "未処理" にならない）' do
              expect(mq1.reload.session_id).to be_nil
              expect(mq2.reload.session_id).not_to be_nil
              expect(mq3.reload.session_id).to be_nil
              expect(mq4.reload.session_id).not_to be_nil
            end
          end

          context 'インスタンスの session_id が、それらレコードの session_id とは異なる場合' do
            let!(:instance_session_id) { 'never match string' }

            it '各レコードは "未処理" 状態にはならない' do
              expect(mq1.reload.session_id).not_to be_nil
              expect(mq2.reload.session_id).not_to be_nil
              expect(mq3.reload.session_id).not_to be_nil
              expect(mq4.reload.session_id).not_to be_nil
            end
          end
        end
      end
    end

    describe '#perform' do
      let!(:instance) { described_class.new(session_id: instance_session_id) }

      context 'session_id がいろいろなレコードが 4件 ある場合' do
        let!(:mq1) { FactoryBot.create(:mail_queue, session_id: 'aaa') }
        let!(:mq2) { FactoryBot.create(:mail_queue, session_id: 'aaa') }
        let!(:mq3) { FactoryBot.create(:mail_queue, session_id: 'bbb') }
        let!(:mq4) { FactoryBot.create(:mail_queue, session_id: 'ccc') }

        context 'インスタンスの session_id が、 2件 のレコードと同一の場合' do
          let!(:instance_session_id) { 'aaa' }

          it 'その 2件 の mail_queue ごとに #perform_one が計 2回 呼ばれる' do
            expect(instance).to receive(:perform_one).with(mq1).once
            expect(instance).to receive(:perform_one).with(mq2).once
            expect(instance).not_to receive(:perform_one).with(mq3)
            expect(instance).not_to receive(:perform_one).with(mq4)
            instance.perform
          end
        end
      end
    end

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
            instance.perform_one(mail_queue)
            mail_queue.reload
          end

          it 'ステータス 250 以外で保存されている' do
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

          it '送信失敗した error ログと、 DeliveryResponse を作成した info ログが記録される' do
            expect(instance.logger).to receive(:error).with(include("event=deliver.result", "level=error", "mail_queue_id=#{mail_queue.id}", "message=NG sending a message mail_queues.id=[#{mail_queue.id}]"))
            expect(instance.logger).to receive(:info).with(/CREATED DeliveryResponse/)
            instance.perform_one(mail_queue)
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
