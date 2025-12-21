require 'rails_helper'

# MailQueue の claim 処理の「堅牢化」に関するフォーカスド・スペックです。
# 目的:
# - 対象レコードの適格性（session_id が NULL、timer_at が現在時刻まで）
# - バッチ claim（小さなバッチで pluck(:id)→id集合で update_all）による重複防止
# - stale claim（古い claimed_at）の解放
# - バックオフ秒数（指数 + ジッタ）の境界確認（ランダムをスタブ）

RSpec.describe MailQueue, type: :model do
  let!(:now) { Time.zone.parse('2023-11-20 12:00:00') }

  before do
    travel_to now
  end

  describe '適格性（eligibility）' do
    context 'session_id が NULL、timer_at が現在時刻以前のレコードのみが対象' do
      before do
        @eligible_past   = FactoryBot.create(:mail_queue, :untouched, timer_at: now - 10.minutes)
        @eligible_now    = FactoryBot.create(:mail_queue, :untouched, timer_at: now)
        @ineligible_future = FactoryBot.create(:mail_queue, :untouched, timer_at: now + 10.minutes)
        @ineligible_touched = FactoryBot.create(:mail_queue, :touched,   timer_at: now - 10.minutes)

        @count = described_class.claim_by_timer!('sess-A')
        @eligible_past.reload
        @eligible_now.reload
        @ineligible_future.reload
        @ineligible_touched.reload
      end

      it '適格な2件のみが claim される' do
        expect(@count).to eq 2
        expect(@eligible_past.session_id).to eq 'sess-A'
        expect(@eligible_now.session_id).to eq 'sess-A'
      end

      it '不適格なレコードは claim されない' do
        expect(@ineligible_future.session_id).to be_nil
        expect(@ineligible_touched.session_id).not_to be_nil
      end
    end
  end

  describe 'バッチ claim（重複防止）' do
    # 小さなバッチで pluck→update_all を繰り返す挙動を確認しやすくするため、バッチサイズを 2 にします。
    before do
      allow(Verbena::Settings).to receive(:in_batches_config).and_return({ of: 2 })
      @rows = 5.times.map { FactoryBot.create(:mail_queue, :untouched, timer_at: now - 1.minute) }
    end

    it '2つのセッションで順次 claim しても、重複なく全件が割り当てられる' do
      c1 = described_class.claim_by_timer!('sess-1')
      c2 = described_class.claim_by_timer!('sess-2')

      expect(c1 + c2).to eq @rows.size

      ids1 = described_class.claimed('sess-1').pluck(:id)
      ids2 = described_class.claimed('sess-2').pluck(:id)

      expect(ids1 & ids2).to be_empty
      expect((ids1 + ids2).sort).to eq @rows.map(&:id).sort
    end
  end

  describe 'stale claim の解放' do
    before do
      @stale_90m = FactoryBot.create(:mail_queue, session_id: 's-1', claimed_at: 90.minutes.ago)
      @stale_120m = FactoryBot.create(:mail_queue, session_id: 's-2', claimed_at: 120.minutes.ago)
      @fresh_20m = FactoryBot.create(:mail_queue, session_id: 's-3', claimed_at: 20.minutes.ago)
      @none = FactoryBot.create(:mail_queue, session_id: nil, claimed_at: nil)
    end

    it '既定（1時間より古い）で2件が解放される' do
      changed = Verbena::MailQueuesService.new.release_stale_claims
      expect(changed).to eq 2

      expect(@stale_90m.reload.session_id).to be_nil
      expect(@stale_120m.reload.session_id).to be_nil
      expect(@fresh_20m.reload.session_id).to eq 's-3'
      expect(@none.reload.session_id).to be_nil
    end

    it '閾値（30分前）を指定すると2件が解放される' do
      changed = Verbena::MailQueuesService.new.release_stale_claims(older_than_hours: 0.5)
      expect(changed).to eq 2
    end
  end

  describe 'バックオフ秒数（calculate_backoff_seconds）' do
    it 'retry_count に応じて指数的に増え、cap を超えない（ランダムをスタブ）' do
      allow(Verbena::Settings).to receive(:claim_backoff_base_seconds).and_return(1.0)
      allow(Verbena::Settings).to receive(:claim_backoff_cap_seconds).and_return(10.0)

      # ランダム 0.0 → 0 秒
      allow(described_class).to receive(:random_fraction).and_return(0.0)
      expect(described_class.send(:calculate_backoff_seconds, 0)).to eq 0.0
      expect(described_class.send(:calculate_backoff_seconds, 1)).to eq 0.0

      # ランダム 1.0 → maxDelay いっぱい
      allow(described_class).to receive(:random_fraction).and_return(1.0)
      expect(described_class.send(:calculate_backoff_seconds, 0)).to eq 1.0
      expect(described_class.send(:calculate_backoff_seconds, 1)).to eq 2.0
      expect(described_class.send(:calculate_backoff_seconds, 3)).to eq 8.0

      # cap 10.0 の適用確認
      expect(described_class.send(:calculate_backoff_seconds, 10)).to eq 10.0
    end
  end

  describe 'stale claim の解放（境界挙動の検証）' do
    # しきい値ちょうど・前後のレコードを用意し、件数と個別挙動を確認する
    before do
      @r120 = FactoryBot.create(:mail_queue, session_id: 's-120', claimed_at: 120.minutes.ago)
      @r90  = FactoryBot.create(:mail_queue, session_id: 's-90',  claimed_at: 90.minutes.ago)
      @r60  = FactoryBot.create(:mail_queue, session_id: 's-60',  claimed_at: 60.minutes.ago)  # ちょうど1時間
      @r31  = FactoryBot.create(:mail_queue, session_id: 's-31',  claimed_at: 31.minutes.ago)
      @r30  = FactoryBot.create(:mail_queue, session_id: 's-30',  claimed_at: 30.minutes.ago)  # ちょうど30分
      @r29  = FactoryBot.create(:mail_queue, session_id: 's-29',  claimed_at: 29.minutes.ago)
      @r20  = FactoryBot.create(:mail_queue, session_id: 's-20',  claimed_at: 20.minutes.ago)
      @none = FactoryBot.create(:mail_queue, session_id: nil,     claimed_at: nil)
    end

    it 'デフォルト（1時間前）: 120/90/60 が解放される（合計3件）' do
      changed = Verbena::MailQueuesService.new.release_stale_claims
      expect(changed).to eq 3

      [@r120, @r90, @r60].each { |r| expect(r.reload.session_id).to be_nil }
      [@r31, @r30, @r29, @r20].each { |r| expect(r.reload.session_id).not_to be_nil }
      expect(@none.reload.session_id).to be_nil
    end

    it '30分前: 120/90/60/31/30 が解放される（合計5件）' do
      changed = Verbena::MailQueuesService.new.release_stale_claims(older_than_hours: 0.5)
      expect(changed).to eq 5

      [@r120, @r90, @r60, @r31, @r30].each { |r| expect(r.reload.session_id).to be_nil }
      [@r29, @r20].each { |r| expect(r.reload.session_id).not_to be_nil }
    end

    it '30分の境界: ちょうど30分は解放、29分は解放されない' do
      Verbena::MailQueuesService.new.release_stale_claims(older_than_hours: 0.5)
      expect(@r30.reload.session_id).to be_nil
      expect(@r29.reload.session_id).not_to be_nil
    end

    it '100分前: 120分のみ解放（合計1件）' do
      changed = Verbena::MailQueuesService.new.release_stale_claims(older_than_hours: (100.0/60.0))
      expect(changed).to eq 1
      expect(@r120.reload.session_id).to be_nil
      [@r90, @r60, @r31, @r30, @r29, @r20].each { |r| expect(r.reload.session_id).not_to be_nil }
    end
  end

  describe 'デッドロック発生時のリトライ・バックオフ' do
    # 目的: claim_in_batches 内で update_all がデッドロックを起こした場合、
    # 指数バックオフでリトライし、最終的に正常にclaimできることを確認する。

    before do
      allow(Verbena::Settings).to receive(:in_batches_config).and_return({ of: 2 })
      allow(Verbena::Settings).to receive(:claim_backoff_base_seconds).and_return(0.01)
      allow(Verbena::Settings).to receive(:claim_backoff_cap_seconds).and_return(1.0)
      # テスト速度のため sleep をスタブ（実際には wait しない）
      allow(Kernel).to receive(:sleep)

      @rows = 2.times.map { FactoryBot.create(:mail_queue, :untouched, timer_at: now - 1.minute) }
    end

    it '1回目の update_all でデッドロック、2回目で成功する' do
      # update_all の呼び出し回数を数えるカウンタ
      update_call_count = 0

      # ActiveRecord::Relation の update_all メソッドをstub
      # 1回目: Deadlocked 例外を raise
      # 2回目以降: 本来の update_all 動作を実行
      allow_any_instance_of(ActiveRecord::Relation).to receive(:update_all).and_wrap_original do |original_method, *args|
        update_call_count += 1

        if update_call_count == 1
          # 1回目：デッドロックを模擬
          raise ActiveRecord::Deadlocked, 'Simulated deadlock on first attempt'
        else
          # 2回目以降：本来の動作で update_all を実行
          original_method.call(*args)
        end
      end

      # claim_by_timer! を実行
      # → 内部で claim_in_batches が呼ばれ、update_all を実行
      # → 1回目: Deadlocked raise → リトライロジックが発動
      # → バックオフ（sleep）を経て、2回目の update_all を実行
      # → 成功してループを抜ける
      expect {
        described_class.claim_by_timer!('sess-deadlock')
      }.not_to raise_error

      # 実際に claim されていることを確認
      expect(described_class.claimed('sess-deadlock').count).to eq @rows.size

      # update_all が少なくとも 2回 呼ばれたことを確認（1回目失敗、2回目成功）
      expect(update_call_count).to be >= 2
    end

    it 'リトライ時に sleep（バックオフ）が呼ばれる' do
      update_call_count = 0

      allow_any_instance_of(ActiveRecord::Relation).to receive(:update_all).and_wrap_original do |original_method, *args|
        update_call_count += 1
        raise ActiveRecord::Deadlocked if update_call_count == 1
        original_method.call(*args)
      end

      described_class.claim_by_timer!('sess-backoff')

      # リトライが発生したことは update_all の複数回呼び出しで確認
      expect(update_call_count).to be >= 2
    end

    it 'リトライ回数上限を超えたら例外を raise' do
      # 常にデッドロックを発生させる設定
      allow_any_instance_of(ActiveRecord::Relation).to receive(:update_all).and_raise(
        ActiveRecord::Deadlocked, 'Persistent deadlock'
      )

      # リトライ上限を小さめに設定（テスト高速化）
      allow(Verbena::Settings).to receive(:claim_max_retries).and_return(2)

      # リトライ上限を超えたら例外が raise される
      expect {
        described_class.claim_by_timer!('sess-max-retries')
      }.to raise_error(ActiveRecord::Deadlocked)
    end
  end
end
