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
          <<~EML1
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

    describe '#create_mail_queue_with_envelope!' do
      let!(:instance) { described_class.new }

      let(:eml) do
        <<~EML
          From: sender@example.com
          To: recipient@example.com
          Subject: Test Message
          Content-Type: text/plain; charset="UTF-8"

          Test body.
        EML
      end
      let(:envelope_from) { 'custom-from@example.com' }
      let(:envelope_to) { 'custom-to@example.com' }
      let(:timer_at) { Time.zone.parse('2023-11-01 15:30:00') }

      context 'timer_atを指定した場合' do
        before do
          @result = instance.create_mail_queue_with_envelope!(eml, envelope_from, envelope_to, timer_at)
        end

        describe '作成されるレコードについて' do
          it 'mail_queues が 1件 作成される' do
            expect(MailQueue.all.count).to eq 1
          end

          it 'eml_sources が 1件 作成される' do
            expect(EmlSource.all.count).to eq 1
          end
        end

        describe '作成される mail_queues レコードについて' do
          let(:created_mail_queue) { MailQueue.last }

          it 'envelope_from が指定した値である' do
            expect(created_mail_queue.envelope_from).to eq envelope_from
          end

          it 'envelope_to が指定した値である' do
            expect(created_mail_queue.envelope_to).to eq envelope_to
          end

          it 'timer_at が指定した値である' do
            expect(created_mail_queue.timer_at).to eq timer_at
          end

          it 'session_id が nil である' do
            expect(created_mail_queue.session_id).to be_nil
          end

          it 'claimed_at が nil である' do
            expect(created_mail_queue.claimed_at).to be_nil
          end
        end

        describe '作成される eml_sources レコードについて' do
          let(:created_eml_source) { EmlSource.last }

          it 'eml の内容が入力メールの全文である' do
            expect(created_eml_source.eml).to eq eml
          end

          it 'mail_queue と eml_source が関連付けられている' do
            expect(MailQueue.last.eml_source_id).to eq created_eml_source.id
          end
        end

        describe '戻り値について' do
          it 'MailQueue のインスタンスである' do
            expect(@result).to be_a(MailQueue)
          end

          it '作成されたレコードの id と一致する' do
            expect(@result.id).to eq MailQueue.last.id
          end
        end
      end

      context 'timer_atを省略した場合' do
        context 'emlにDateヘッダがある場合' do
          let(:eml) do
            <<~EML
              Date: Wed, 20 Dec 2023 12:34:56 +0900
              From: sender@example.com
              To: recipient@example.com
              Subject: Test
              Content-Type: text/plain; charset="UTF-8"

              body
            EML
          end
          let(:envelope_from) { 'from@example.com' }
          let(:envelope_to) { 'to@example.com' }
          let(:expected_time) { Time.zone.parse('Wed, 20 Dec 2023 12:34:56 +0900') }

          it 'timer_atがemlのDateヘッダの値になる' do
            result = instance.create_mail_queue_with_envelope!(eml, envelope_from, envelope_to)
            expect(result.timer_at).to eq expected_time
          end
        end

        context 'emlにDateヘッダがない場合' do
          let(:eml) do
            <<~EML
              From: sender@example.com
              To: recipient@example.com
              Subject: Test
              Content-Type: text/plain; charset="UTF-8"

              body
            EML
          end
          let(:envelope_from) { 'from@example.com' }
          let(:envelope_to) { 'to@example.com' }
          let(:now) { Time.zone.parse('2023-12-21 15:00:00') }

          before { travel_to now }

          it 'timer_atが現在時刻になる' do
            result = instance.create_mail_queue_with_envelope!(eml, envelope_from, envelope_to)
            expect(result.timer_at).to eq now
          end
        end
      end

      context 'トランザクションのロールバックが必要な場合' do
        before do
          # EmlSource 作成後、MailQueue 作成時にエラーを発生させる
          allow_any_instance_of(EmlSource).to receive_message_chain(:mail_queues, :create!).and_raise(ActiveRecord::StatementInvalid)
        end

        it '例外が発生する' do
          expect {
            instance.create_mail_queue_with_envelope!(eml, envelope_from, envelope_to, timer_at)
          }.to raise_error(ActiveRecord::StatementInvalid)
        end

        it 'mail_queues が作成されない' do
          begin
            instance.create_mail_queue_with_envelope!(eml, envelope_from, envelope_to, timer_at)
          rescue ActiveRecord::StatementInvalid
            # 例外を握りつぶす
          end

          expect(MailQueue.all.count).to eq 0
        end

        it 'eml_sources も作成されない（トランザクションがロールバックされる）' do
          begin
            instance.create_mail_queue_with_envelope!(eml, envelope_from, envelope_to, timer_at)
          rescue ActiveRecord::StatementInvalid
            # 例外を握りつぶす
          end

          expect(EmlSource.all.count).to eq 0
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

    describe '#release_stale_claims' do
      let!(:instance) { described_class.new }

      shared_context 'with_claimed_and_delivered_records' do
        let(:now) { Time.zone.parse('2023-10-23 12:00:00') }

        before do
          travel_to now
          # 対象: 古い claim（未配送・session_idあり）
          @stale1 = FactoryBot.create(:mail_queue, session_id: 's1', claimed_at: now - 2.hours)
          @stale2 = FactoryBot.create(:mail_queue, session_id: 's2', claimed_at: now - 80.minutes)
          # 閾値ちょうど: claimed_at が now - 30.minutes ぴったり（境界値テスト用）
          @fresh = FactoryBot.create(:mail_queue, session_id: 'fresh', claimed_at: now - 30.minutes)
          # 対象外: claimされていない
          @unclaimed = FactoryBot.create(:mail_queue, session_id: nil, claimed_at: nil)
          # 対象外: 配送済み
          @delivered = FactoryBot.create(:mail_queue, session_id: 'delivered', claimed_at: now - 2.hours)
          FactoryBot.create(:delivery_response, mail_queue: @delivered)
        end
      end

      context 'dry_run と実行結果が一致すること（デフォルト1時間）' do
        include_context 'with_claimed_and_delivered_records'

        it 'dry_runの件数と実行の更新件数が等しい' do
          dry = instance.count_stale_claims
          expect(dry).to eq 2

          changed = instance.release_stale_claims!
          expect(changed).to eq dry

          expect(MailQueue.find(@stale1.id).session_id).to be_nil
          expect(MailQueue.find(@stale2.id).session_id).to be_nil
          expect(MailQueue.find(@fresh.id).session_id).to eq 'fresh'
          expect(MailQueue.find(@delivered.id).session_id).to eq 'delivered'
        end
      end

      context 'dry_run と実行結果が一致すること（閾値を30分に変更）' do
        include_context 'with_claimed_and_delivered_records'

        it 'dry_runの件数と実行の更新件数が等しい（30分ちょうども含む）' do
          dry = instance.count_stale_claims(older_than_hours: 0.5)
          # 30分「以前（含む）」は stale1, stale2, fresh(ちょうど30分) の3件
          expect(dry).to eq 3

          changed = instance.release_stale_claims!(older_than_hours: 0.5)
          expect(changed).to eq dry
        end
      end

      context '引数バリデーション' do
        include_context 'with_claimed_and_delivered_records'

        it '数値に変換可能な文字列を受け付ける' do
          expect(instance.count_stale_claims(older_than_hours: '0.5')).to eq 3
        end

        it 'nil はデフォルトの 1.0 として扱う' do
          expect(instance.count_stale_claims(older_than_hours: nil)).to eq 2
        end

        it '負の値は NegativeClaimHoursError を送出する' do
          expect {
            instance.count_stale_claims(older_than_hours: -1)
          }.to raise_error(Verbena::MailQueuesService::NegativeClaimHoursError, 'older_than_hours must be >= 0')
        end

        it 'normalize_hours_arg は型変換のみ行い、負値もそのまま返す（負値検証は release_stale_claims 側）' do
          expect(described_class.normalize_hours_arg(-1)).to eq(-1.0)
        end

        it '非数値文字列は ArgumentError を送出する (Float による例外が伝播する)' do
          expect {
            instance.count_stale_claims(older_than_hours: 'abc')
          }.to raise_error(ArgumentError)
        end
      end
    end

    describe '#show_stale_claims' do
      let!(:instance) { described_class.new }
      let!(:now) { Time.zone.parse('2023-12-21 12:00:00') }

      before do
        travel_to now
        # stale: claimed, not delivered
        @stale1 = FactoryBot.create(:mail_queue, session_id: 's1', claimed_at: 2.hours.ago, envelope_to: 'a@example.com')
        @stale2 = FactoryBot.create(:mail_queue, session_id: 's2', claimed_at: 1.hour.ago, envelope_to: 'b@example.com')
        # not stale: not claimed
        @unclaimed = FactoryBot.create(:mail_queue, session_id: nil, claimed_at: nil, envelope_to: 'c@example.com')
        # not stale: delivered
        @delivered = FactoryBot.create(:mail_queue, session_id: 'd', claimed_at: 3.hours.ago, envelope_to: 'd@example.com')
        FactoryBot.create(:delivery_response, mail_queue: @delivered)
      end

      it 'claimed_at が未来の場合（age_seconds が負の場合）NegativeAgeError 例外が発生すること' do
        FactoryBot.create(:mail_queue, session_id: 'future', claimed_at: now + 1.hour, envelope_to: 'future@example.com')
        expect {
          instance.show_stale_claims
        }.to raise_error(Verbena::MailQueuesService::NegativeAgeError, /Negative age_seconds detected/)
      end

      it '未配送かつ claim 中のレコードのみ返し、フィールド内容も正しいこと' do
        result = instance.show_stale_claims
        expect(result.size).to eq 2
        ids = result.map { |h| h[:id] }
        expect(ids).to contain_exactly(@stale1.id, @stale2.id)
        result.each do |rec|
          expect(rec).to include(:id, :session_id, :claimed_at, :envelope_to, :age_seconds)
          expect(rec[:age_seconds]).to be_within(1).of(now - rec[:claimed_at])
        end
      end

      it '該当レコードがない場合は空配列を返すこと' do
        MailQueue.update_all(session_id: nil, claimed_at: nil)
        expect(instance.show_stale_claims).to eq([])
      end
    end

    describe 'file-based wrappers' do
      let!(:instance) { described_class.new }
      let(:path) { '/tmp/fake.eml' }
      let(:eml_content) { "From: sender@example.com\r\nTo: recipient@example.com\r\n\r\nHello" }

      describe '#create_mail_queues_from_file!' do
        it 'reads EML via reader and delegates to create_mail_queues_by_eml!' do
          allow(instance).to receive(:read_eml_from_file!).with(path).and_return(eml_content)
          expect(instance).to receive(:create_mail_queues_by_eml!).with(eml_content).and_return([:mq])

          result = instance.create_mail_queues_from_file!(path)
          expect(result).to eq([:mq])
        end

        it 'propagates reader errors' do
          allow(instance).to receive(:read_eml_from_file!).with(path).and_raise(Verbena::EmlFileReader::MissingPathError.new('eml file path is required'))
          expect { instance.create_mail_queues_from_file!(path) }.to raise_error(Verbena::EmlFileReader::MissingPathError)
        end
      end

      describe '#create_mail_queue_from_file_with_envelope!' do
        it 'reads EML via reader and delegates to create_mail_queue_with_envelope!' do
          allow(instance).to receive(:read_eml_from_file!).with(path).and_return(eml_content)
          dummy = MailQueue.new
          expect(instance).to receive(:create_mail_queue_with_envelope!).with(eml_content, 'from@example.com', 'to@example.com', nil).and_return(dummy)

          result = instance.create_mail_queue_from_file_with_envelope!(path, 'from@example.com', 'to@example.com', nil)
          expect(result).to be(dummy)
        end

        it 'propagates reader errors' do
          allow(instance).to receive(:read_eml_from_file!).with(path).and_raise(Verbena::EmlFileReader::FileNotFoundError.new('File not found'))
          expect { instance.create_mail_queue_from_file_with_envelope!(path, 'f', 't', nil) }.to raise_error(Verbena::EmlFileReader::FileNotFoundError)
        end
      end
    end
  end
end
