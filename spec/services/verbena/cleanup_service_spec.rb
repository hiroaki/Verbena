require 'rails_helper'

RSpec.describe Verbena::CleanupService, type: :service do
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

    describe 'オプション設定' do
      let!(:instance) { described_class.new(opts) }

      context 'オプションに { expiration: "2023-10-23" } を渡す場合' do
        let!(:opts) { { expiration: "2023-10-23" } }
        it 'インスタンス化できる' do
          expect(instance).to be_a(described_class)
        end
      end

      context 'オプションに { foo: "bar" } を渡す場合' do
        let!(:opts) { { foo: "bar" } }
        it 'インスタンス化できる' do
          expect(instance).to be_a(described_class)
        end
      end
    end
  end

  describe 'クラスメソッド' do
    describe '.now' do
      describe '返却値について' do
        subject { described_class.now }
        it 'インスタンスが返る' do
          is_expected.to be_a described_class
        end
      end

      describe 'expiration について' do
        subject { described_class.now.expiration }
        it '現在時刻である' do
          is_expected.to eq(genzai_jikoku)
        end
      end
    end

    describe '.daily' do
      describe '返却値について' do
        subject { described_class.daily }
        it 'インスタンスが返る' do
          is_expected.to be_a described_class
        end
      end

      describe 'expiration について' do
        subject { described_class.daily.expiration }
        it '一日前の日時である' do
          is_expected.to eq(genzai_jikoku - 1.day)
        end
      end
    end

    describe '.weekly' do
      describe '返却値について' do
        subject { described_class.weekly }
        it 'インスタンスが返る' do
          is_expected.to be_a described_class
        end
      end

      describe 'expiration について' do
        subject { described_class.weekly.expiration }
        it '一週前の日時である' do
          is_expected.to eq(genzai_jikoku - 1.week)
        end
      end
    end

    describe '.monthly' do
      describe '返却値について' do
        subject { described_class.monthly }
        it 'インスタンスが返る' do
          is_expected.to be_a described_class
        end
      end

      describe 'expiration について' do
        subject { described_class.monthly.expiration }
        it '一月前の日時である' do
          is_expected.to eq(genzai_jikoku - 1.month)
        end
      end
    end

    describe '.by_ttl' do
      before do
        allow(Verbena::Settings).to receive(:cleanup_ttl_days).and_return(45)
      end

      describe '返却値について' do
        subject { described_class.by_ttl }
        it 'インスタンスが返る' do
          is_expected.to be_a described_class
        end
      end

      describe 'expiration について' do
        subject { described_class.by_ttl.expiration }
        it '設定の TTL 日数ぶん過去である' do
          is_expected.to eq(genzai_jikoku - 45.days)
        end
      end
    end
  end

  describe 'インスタンスメソッド' do
    describe '#expiration' do
      let!(:instance) { described_class.new(expiration: expiration) }

      subject { instance.expiration }

      context do
        let!(:expiration) { genzai_jikoku }
        it { is_expected.to eq genzai_jikoku }
      end

      context do
        let!(:expiration) { genzai_jikoku - 1.day }
        it { is_expected.to eq genzai_jikoku - 1.day }
      end
    end

    describe '#expiration=' do
      let!(:instance) { described_class.new(expiration: genzai_jikoku) }

      subject { instance.expiration = value; instance.expiration }

      context do
        let!(:value) { genzai_jikoku - 1.day }
        it { is_expected.to eq(genzai_jikoku - 1.day) }
      end

      context do
        let!(:value) { '2023-10-23 12:33:44' }
        it { is_expected.to eq Time.zone.parse('2023-10-23 12:33:44') }
      end

      context do
        let!(:value) { '2023-10-23' }
        it { is_expected.to eq Time.zone.parse('2023-10-23') }
      end

      context do
        let!(:value) { '2023-10-23 12:00:00 +09:00' }
        it { is_expected.to eq Time.zone.parse('2023-10-23 03:00:00 UTC') }
      end

      context do
        let!(:value) { nil }
        it { expect { subject }.to raise_error(ArgumentError) }
      end

      context do
        let!(:value) { '' }
        it { expect { subject }.to raise_error(ArgumentError) }
      end

      context do
        let!(:value) { 'AAA' }
        it { expect { subject }.to raise_error(ArgumentError) }
      end
    end

    describe '#cleanup' do
      let!(:instance) { described_class.new }

      it '#cleanup_mail_queues を呼び、そのあとに #cleanup_eml_sources を呼ぶ' do
        expect(instance).to receive(:cleanup_mail_queues).ordered
        expect(instance).to receive(:cleanup_eml_sources).ordered
        instance.cleanup
      end
    end

    describe '#cleanup_mail_queues' do
      context '保存期限が 2日 の場合' do
        let!(:instance) { described_class.new(expiration: genzai_jikoku - 2.days) }

        describe '削除対象の条件について' do
          # 削除対象となる条件を満たさない（未処理である）
          context '未処理の mail_queue が 1件 ある場合（かつ、関連する delivery_responses が 1件 ある場合）' do
            before do
              mq = FactoryBot.create(:mail_queue, :untouched)

              # 一度配送処理が行われたあとで見かけ上の状態が未処理に見えても、
              # `delivery_responses` が存在するレコードは「処理済み」と見なされ、削除対象にならないことを確認します。
              FactoryBot.create(:delivery_response, mail_queue: mq, responded_at: genzai_jikoku - 2.days)
            end

            it '処理後の件数は mail_queues が 1件 delivery_responses が 0件 である' do
              expect(MailQueue.all.size).to eq 1
              expect(DeliveryResponse.all.size).to eq 1
              instance.cleanup_mail_queues
              expect(MailQueue.all.size).to eq 1
              expect(DeliveryResponse.all.size).to eq 1
            end
          end

          context '処理中ステータスの mail_queue が 1件 あり、保存期限切れのレスポンスがある場合' do
            before do
              mq = FactoryBot.create(:mail_queue, :touched)
              mq.update!(delivery_status: :processing)
              FactoryBot.create(:delivery_response, mail_queue: mq, responded_at: genzai_jikoku - 3.days)
            end

            it '処理中のため削除対象から除外される' do
              expect(MailQueue.count).to eq 1
              instance.cleanup_mail_queues
              expect(MailQueue.count).to eq 1
            end
          end

          # 削除対象となる条件を満たさない（保存期限切れではない）
          context '2日前に処理済みが 1件 ある場合' do
            before do
              mq = FactoryBot.create(:mail_queue, :touched)
              FactoryBot.create(:delivery_response, mail_queue: mq, responded_at: genzai_jikoku - 2.days)
            end

            it '処理後の件数は mail_queues が 1件 delivery_responses が 1件 である' do
              expect(MailQueue.all.size).to eq 1
              expect(DeliveryResponse.all.size).to eq 1
              instance.cleanup_mail_queues
              expect(MailQueue.all.size).to eq 1
              expect(DeliveryResponse.all.size).to eq 1
            end
          end

          # 削除対象となる条件を満たす場合（処理済み、かつ保存期限切れ）
          context '3日前に処理済みが 1件 ある場合' do
            before do
              mq = FactoryBot.create(:mail_queue, :touched)
              FactoryBot.create(:delivery_response, mail_queue: mq, responded_at: genzai_jikoku - 3.days)
            end

            it '処理後の件数は mail_queues が 0件 delivery_responses が 0件 である' do
              expect(MailQueue.all.size).to eq 1
              expect(DeliveryResponse.all.size).to eq 1
              instance.cleanup_mail_queues
              expect(MailQueue.all.size).to eq 0
              expect(DeliveryResponse.all.size).to eq 0
            end
          end
        end

        describe '複数レコードの処理について' do
          context '未処理1件 2日前に処理済み1件 3日前に処理済み1件 の mail_queues がある場合' do
            before 'mail_queue' do
              mq1 = FactoryBot.create(:mail_queue, :untouched)
              mq2 = FactoryBot.create(:mail_queue, :touched)
              mq3 = FactoryBot.create(:mail_queue, :touched)

              dr2 = FactoryBot.create(:delivery_response, mail_queue: mq2, responded_at: genzai_jikoku - 2.days)
              dr3 = FactoryBot.create(:delivery_response, mail_queue: mq3, responded_at: genzai_jikoku - 3.days)
            end

            it '処理後の件数は mail_queues が 2件 delivery_responses が 1件 である' do
              expect(MailQueue.all.size).to eq 3
              expect(DeliveryResponse.all.size).to eq 2
              instance.cleanup_mail_queues
              expect(MailQueue.all.size).to eq 2
              expect(DeliveryResponse.all.size).to eq 1
            end
          end
        end
      end
    end

    describe '#cleanup_eml_sources' do
      let!(:instance) { described_class.new }

      context 'mail_queues が 3件 あり、それぞれ別々の eml_source を参照している場合' do
        before do
          mq1 = FactoryBot.create(:mail_queue, :untouched)
          mq2 = FactoryBot.create(:mail_queue, :untouched)
          mq3 = FactoryBot.create(:mail_queue, :untouched)
        end

        it '処理後の件数は eml_source が 3件 である' do
          instance.cleanup_eml_sources
          expect(EmlSource.all.size).to eq 3
        end
      end

      context '3 件の mail_queues A B C と 2 件の eml_sources D E があり、 A は eml_source(D) 、 B C は共に eml_source(E) を参照している場合' do
        before do
          @esD = FactoryBot.create(:eml_source)
          @esE = FactoryBot.create(:eml_source)
          @mqA = FactoryBot.create(:mail_queue, :untouched, eml_source: @esD)
          @mqB = FactoryBot.create(:mail_queue, :untouched, eml_source: @esE)
          @mqC = FactoryBot.create(:mail_queue, :untouched, eml_source: @esE)
        end

        context 'その状態で処理する場合' do
          before do
            instance.cleanup_eml_sources
          end

          it '処理後の件数は eml_source が 2件 である' do
            expect(EmlSource.all.size).to eq 2
          end
        end

        context 'mail_queues A を削除したうえで処理する場合' do
          before do
            @mqA.destroy!
            instance.cleanup_eml_sources
          end

          it '処理後の件数は eml_source が 1件 である' do
            expect(EmlSource.all.size).to eq 1
          end
        end

        context 'mail_queues B を削除したうえで処理する場合' do
          before do
            @mqB.destroy!
            instance.cleanup_eml_sources
          end

          it '処理後の件数は eml_source が 2件 である' do
            expect(EmlSource.all.size).to eq 2
          end
        end

        context 'mail_queues C を削除したうえで処理する場合' do
          before do
            @mqC.destroy!
            instance.cleanup_eml_sources
          end

          it '処理後の件数は eml_source が 2件 である' do
            expect(EmlSource.all.size).to eq 2
          end
        end

        context 'mail_queues B C を削除したうえで処理する場合' do
          before do
            @mqB.destroy!
            @mqC.destroy!
            instance.cleanup_eml_sources
          end

          it '処理後の件数は eml_source が 1件 である' do
            expect(EmlSource.all.size).to eq 1
          end
        end

        context 'mail_queues A B C を削除したうえで処理する場合' do
          before do
            @mqA.destroy!
            @mqB.destroy!
            @mqC.destroy!
            instance.cleanup_eml_sources
          end

          it '処理後の件数は eml_source が 0件 である' do
            expect(EmlSource.all.size).to eq 0
          end
        end
      end
    end

    describe 'dry-run' do
      context '保存期限 2日・dry_run=true の場合' do
        let!(:expiration) { genzai_jikoku - 2.days }
        let!(:instance) { described_class.new(expiration: expiration, dry_run: true) }

        before do
          # mail_queues（削除対象1件・非対象2件）
          mq_untouched = FactoryBot.create(:mail_queue, :untouched)
          FactoryBot.create(:delivery_response, mail_queue: mq_untouched, responded_at: genzai_jikoku - 3.days)

          mq_recent = FactoryBot.create(:mail_queue, :touched)
          FactoryBot.create(:delivery_response, mail_queue: mq_recent, responded_at: genzai_jikoku - 1.day)

          mq_old = FactoryBot.create(:mail_queue, :touched)
          FactoryBot.create(:delivery_response, mail_queue: mq_old, responded_at: genzai_jikoku - 3.days)

          # eml_sources（未参照のものを1件用意）
          FactoryBot.create(:eml_source) # 参照なし → 対象 1 件
        end

        it 'cleanup は件数のハッシュを返し、レコードは削除されない' do
          total_mq_before = MailQueue.count
          total_dr_before = DeliveryResponse.count
          total_es_before = EmlSource.count

          result = instance.cleanup

          expect(result).to include(:mail_queues, :eml_sources)
          expect(result[:mail_queues]).to eq 1 # 古い処理済み1件（processing/pendingは除外）
          expect(result[:eml_sources]).to eq 1 # 未参照1件

          # dry-run のため削除は行われない
          expect(MailQueue.count).to eq total_mq_before
          expect(DeliveryResponse.count).to eq total_dr_before
          expect(EmlSource.count).to eq total_es_before
        end
      end
    end
  end
end
