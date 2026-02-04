require 'rails_helper'

RSpec.describe Verbena::MailQueuesService, type: :service do
  include ActiveJob::TestHelper

  let!(:genzai_jikoku) { Time.zone.parse('2023-10-23 10:11:22') }
  let(:token) { FactoryBot.create(:token) }

  before do
    travel_to genzai_jikoku
  end

  describe 'コンストラクタ' do
    describe 'Tokenあり' do
      it 'インスタンス化できる' do
        expect(described_class.new(token: token)).to be_a(described_class)
      end
    end

    describe 'Tokenなし' do
      it 'ArgumentErrorが発生する' do
        expect { described_class.new }.to raise_error(ArgumentError, /Token is required/)
        expect { described_class.new(token: nil) }.to raise_error(ArgumentError, /Token is required/)
      end
    end
  end

  describe 'インスタンスメソッド' do
    let!(:instance) { described_class.new(token: token) }

    describe '#create_mail_queues_by_eml!' do
      context '宛先が四件(To:1,Cc:2,Bcc:1)あるメールの場合' do
        let!(:eml) do
          <<~EML1
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

        let!(:header_date) { Time.zone.parse('Tue, 1 Jul 2003 10:52:37 +0200') }

        describe '4件のうちで例外が発生しない場合' do
          before do
            ActiveJob::Base.queue_adapter = :test
            clear_enqueued_jobs
            @result = instance.create_mail_queues_by_eml!(eml)
          end

          describe '作成されるレコードとジョブについて' do
            it 'mail_queues が 4件 作成される' do
              expect(MailQueue.all.count).to eq 4
            end

            it '作成された mail_queues は全て指定した token に紐づいている' do
              expect(MailQueue.all.pluck(:token_id).uniq).to eq [token.id]
            end

            it 'envelope_to が EML の宛先の4件をカバーしている' do
              expect(MailQueue.all.pluck(:envelope_to)).to contain_exactly('you@example.com', 'ichiro@example.com', 'jirou@example.com', 'saburo@example.com')
            end

            it 'envelope_from が、いずれも me@example.com である' do
              expect(MailQueue.all.pluck(:envelope_from)).to all(eq 'me@example.com')
            end

            it 'eml_source_id が、すべて同一である' do
              expect(MailQueue.all.pluck(:eml_source_id).uniq.size).to eq 1
            end

            it 'DeliveryJob が 4件 エンキューされる' do
              expect(DeliveryJob).to have_been_enqueued.exactly(4).times
            end

            it 'eml_sources が 1件 作成される' do
              expect(EmlSource.all.count).to eq 1
            end
          end

          describe '作成される mail_queues レコード 4件 について' do
            it 'timer_at が、いずれも Date: ヘッダの値の日時 である' do
              expect(MailQueue.all.pluck(:timer_at)).to all(eq header_date)
            end

            it '関連する eml の内容が入力メールの全文である' do
              expect(MailQueue.last.eml).to eq eml
            end
          end

          describe '戻り値について' do
            it '4件の MailQueue のインスタンスを返す' do
              expect(@result.map(&:class)).to all(eq(MailQueue))
            end

            it 'MailQueue のインスタンスの id が、作成されたレコードの id に等しい' do
              expect(@result.map(&:id)).to match_array(MailQueue.pluck(:id))
            end
          end
        end
      end

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

      context 'Date: が記述されていないメールの場合' do
        let!(:eml) do
          <<~EML1
            From: me@example.com
            To: you@example.com
            Subject: =?UTF-8?Q?=E3=81=94=E6=8C=A8=E6=8B=B6?=
            Content-Type: text/plain; charset="UTF-8"

            こんにちは。
          EML1
        end

        it 'timer_at が現在時刻になる' do
          result = instance.create_mail_queues_by_eml!(eml)
          expect(result.first.timer_at).to eq genzai_jikoku
        end
      end
    end

    describe '#create_mail_queue_with_envelope!' do
      let(:eml) { "From: sender@example.com\r\nTo: recipient@example.com\r\n\r\nHello" }

      it '指定された token に紐づく MailQueue が作成される' do
        result = instance.create_mail_queue_with_envelope!(eml, 'sender@example.com', 'recipient@example.com')
        expect(result.token_id).to eq(token.id)
        expect(MailQueue.count).to eq(1)
      end

      context 'timer_at を明示指定した場合' do
        let(:timer_at) { Time.zone.parse('2023-11-01 15:30:00') }

        it 'envelope と timer_at が指定値で保存される' do
          result = instance.create_mail_queue_with_envelope!(eml, 'from@example.com', 'to@example.com', timer_at)
          expect(result.envelope_from).to eq 'from@example.com'
          expect(result.envelope_to).to eq 'to@example.com'
          expect(result.timer_at).to eq timer_at
          expect(result.claimed_at).to be_nil
        end
      end

      context 'timer_at を省略し、eml に Date ヘッダがある場合' do
        let(:eml) do
          <<~EML
            Date: Wed, 20 Dec 2023 12:34:56 +0900
            From: sender@example.com
            To: recipient@example.com

            body
          EML
        end

        it 'timer_at が Date ヘッダの値になる' do
          result = instance.create_mail_queue_with_envelope!(eml, 'from@example.com', 'to@example.com')
          expect(result.timer_at).to eq Time.zone.parse('Wed, 20 Dec 2023 12:34:56 +0900')
        end
      end

      context 'timer_at を省略し、eml に Date ヘッダがない場合' do
        let(:now) { Time.zone.parse('2023-12-21 15:00:00') }
        let(:eml) do
          <<~EML
            From: sender@example.com
            To: recipient@example.com

            body
          EML
        end

        before { travel_to now }

        it 'timer_at が現在時刻になる' do
          result = instance.create_mail_queue_with_envelope!(eml, 'from@example.com', 'to@example.com')
          expect(result.timer_at).to eq now
        end
      end

      context 'MailQueue 作成で例外が発生する場合' do
        it 'トランザクションがロールバックされ eml_sources が残らない' do
          allow_any_instance_of(Token).to receive_message_chain(:mail_queues, :create!).and_raise(ActiveRecord::StatementInvalid)
          expect {
            instance.create_mail_queue_with_envelope!(eml, 'from@example.com', 'to@example.com', nil)
          }.to raise_error(ActiveRecord::StatementInvalid)
          expect(EmlSource.count).to eq 0
        end
      end
    end

    describe '#destroy_mail_queue_by_id!' do
      context 'mail_queues レコードが 1件 ある場合' do
        let!(:mail_queue) { FactoryBot.create(:mail_queue, token: token) }
        let!(:other_token) { FactoryBot.create(:token) }
        let!(:other_mail_queue) { FactoryBot.create(:mail_queue, token: other_token) }

        context '自分のトークンのレコード id を指定する場合' do
          before do
            instance.destroy_mail_queue_by_id!(mail_queue.id)
          end

          it '指定したレコードが削除される' do
            expect(MailQueue.find_by(id: mail_queue.id)).to be_nil
          end
        end

        context '他人のトークンのレコード id を指定する場合' do
          it '例外 ActiveRecord::RecordNotFound が投げられる' do
            expect { instance.destroy_mail_queue_by_id!(other_mail_queue.id) }.to raise_error(ActiveRecord::RecordNotFound)
          end

          it 'レコードは削除されない' do
            begin
              instance.destroy_mail_queue_by_id!(other_mail_queue.id)
            rescue ActiveRecord::RecordNotFound
            end
            expect(MailQueue.find_by(id: other_mail_queue.id)).not_to be_nil
          end
        end

        context '存在しないレコードの id を指定する場合' do
          it '例外 ActiveRecord::RecordNotFound が投げられる' do
            non_existent_id = MailQueue.maximum(:id).to_i + 9999
            expect { instance.destroy_mail_queue_by_id!(non_existent_id) }.to raise_error(ActiveRecord::RecordNotFound)
          end
        end
      end
    end

    describe '#destroy_mail_queue!' do
      let!(:mail_queue) { FactoryBot.create(:mail_queue, token: token) }

      it '指定したレコードを削除する' do
        instance.destroy_mail_queue!(mail_queue)
        expect(MailQueue.find_by(id: mail_queue.id)).to be_nil
      end
    end

    describe 'file-based wrappers' do
      let(:path) { '/tmp/fake.eml' }
      let(:eml_content) { "From: sender@example.com\r\nTo: recipient@example.com\r\n\r\nHello" }

      describe '#create_mail_queues_from_file!' do
        it 'reads EML via reader and delegates to create_mail_queues_by_eml!' do
          allow(instance).to receive(:read_eml_from_file!).with(path).and_return(eml_content)
          expect(instance).to receive(:create_mail_queues_by_eml!).with(eml_content).and_return([:mq])

          result = instance.create_mail_queues_from_file!(path)
          expect(result).to eq([:mq])
        end

        it 'reader エラーを伝播する' do
          allow(instance).to receive(:read_eml_from_file!).with(path).and_raise(Verbena::EmlFileReader::MissingPathError.new('eml file path is required'))
          expect { instance.create_mail_queues_from_file!(path) }.to raise_error(Verbena::EmlFileReader::MissingPathError)
        end
      end

      describe '#create_mail_queue_from_file_with_envelope!' do
        it 'reader で読み込んだ EML を create_mail_queue_with_envelope! に委譲する' do
          allow(instance).to receive(:read_eml_from_file!).with(path).and_return(eml_content)
          dummy = MailQueue.new
          expect(instance).to receive(:create_mail_queue_with_envelope!).with(eml_content, 'from@example.com', 'to@example.com', nil).and_return(dummy)

          result = instance.create_mail_queue_from_file_with_envelope!(path, 'from@example.com', 'to@example.com', nil)
          expect(result).to be(dummy)
        end

        it 'reader エラーを伝播する' do
          allow(instance).to receive(:read_eml_from_file!).with(path).and_raise(Verbena::EmlFileReader::FileNotFoundError.new('File not found'))
          expect { instance.create_mail_queue_from_file_with_envelope!(path, 'f', 't', nil) }.to raise_error(Verbena::EmlFileReader::FileNotFoundError)
        end
      end
    end

  end
end
