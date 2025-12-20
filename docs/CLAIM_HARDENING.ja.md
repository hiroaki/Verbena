(Claude Sonnet 4.5 による翻訳版)
---

# MailQueue.claim! 強化実装ドキュメント

このドキュメントは、`MailQueue.claim!` の強化実装について、並行実行の安全性と自動的なスタックレコード回復の仕組みを日本語で解説します。

## 概要

従来の `claim!` メソッドは単純な `update_all` に依存しており、並行環境ではレースコンディションが発生する可能性がありました。本実装では以下の点を強化しています：

1. **アトミックなバッチ処理**：IDを先に小分けで取得し、IDセットで更新することでロック競合を低減
2. **デッドロック回復**：指数バックオフ＋ジッターでデッドロック時に自動リトライ（デフォルト: base=1秒, cap=300秒）
3. **スタック検出**：`claimed_at` カラムでクレーム時刻を記録し、自動回復を実現
4. **運用ツール**：保守・監視用のrakeタスクを提供

## DB変更

### マイグレーション: `20250902120000_add_claimed_at_to_mail_queues.rb`

```ruby
class AddClaimedAtToMailQueues < ActiveRecord::Migration[7.1]
  def change
    add_column :mail_queues, :claimed_at, :datetime
    # クレーム操作時の効率化のためインデックス追加
    add_index :mail_queues, :session_id
    add_index :mail_queues, :claimed_at
    add_index :mail_queues, [:session_id, :claimed_at]
    add_index :mail_queues, [:timer_at, :session_id]
  end
end
```

**新カラム:**
- `claimed_at`: セッションによるクレーム時刻。スタック検出に利用。

**新インデックス:**
- `session_id`: セッション単位の検索高速化
- `claimed_at`: スタック検出の効率化
- `session_id + claimed_at`: セッションクリーンアップ用複合インデックス
- `timer_at + session_id`: タイマー配送用の最適化

## モデルメソッドの強化

### コアクレームロジック

強化版 `claim!` メソッドは：

1. **小バッチで処理**（デフォルト20件）でロック時間を短縮
2. **デッドロック時はリトライ**（指数バックオフ）
3. **`claimed_at` 設定**でスタック検出
4. **アトミック操作**でレース防止

```ruby
# 内部メソッド - バッチでクレーム処理
# 小分けでIDを取得し、IDセットで更新
# タイムスタンプ：
# - claimed_at: セッションごとに一貫した時刻
# - updated_at: 更新時にTime.current

def self.claim_in_batches(session_id, condition)
  batch_size   = claim_batch_size
  max_retries  = claim_max_retries
  total_claimed = 0
  current_time = Time.current

  retries = 0

  loop do
    ids = where(condition.merge(session_id: nil)).order(:id).limit(batch_size).pluck(:id)
    break if ids.empty?

    begin
      claimed_count = where(id: ids, session_id: nil).update_all(
        session_id: session_id,
        claimed_at: current_time,
        updated_at: Time.current
      )

      total_claimed += claimed_count
      break if ids.length < batch_size
      retries = 0
    rescue ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout => e
      if retries < max_retries
        backoff_seconds = calculate_backoff_seconds(retries)
        Rails.logger.warn("[MailQueue] Deadlock detected, retrying in #{backoff_seconds}s")
        sleep(backoff_seconds)
        retries += 1
        next
      else
        Rails.logger.error("[MailQueue] Max retries exceeded: #{e.message}")
        raise
      end
    end
  end

  total_claimed
end
```

### スタックレコード管理

```ruby
# 指定時間より古いクレームを解放（デフォルト1時間）
def self.release_stale_claims!(older_than: 1.hour.ago)
  stale_count = where(claimed_at: ..older_than)
                .where.not(session_id: nil)
                .update_all(session_id: nil, claimed_at: nil, updated_at: Time.current)

  Rails.logger.info("[MailQueue] Released #{stale_count} stale claims") if stale_count > 0
  stale_count
end

# クレーム済みだが配送結果がない（処理が詰まっている）レコードを検索
def self.claimed_but_undelivered
  left_outer_joins(:delivery_responses)
    .where.not(session_id: nil)
    .where(delivery_responses: { id: nil })
end
```

## Rakeタスク

### スタッククレームのクリーンアップ

```bash
# 1時間より古いスタッククレームを解放（ドライラン）
rails verbena:claim:release_stale[1,dry]

# 2時間より古いスタッククレームを解放（実行）
rails verbena:claim:release_stale[2]

# 現在のスタッククレームを表示
rails verbena:claim:show_stale
```

### 出力例

```bash
$ rails verbena:claim:show_stale
Found 3 claimed but undelivered records:
ID      Session ID      Claimed At              Envelope To             Age
--------------------------------------------------------------------------------
1001    abc12345...     2023-10-23 10:15:22     user@example.com        2h15m30s
1002    def67890...     2023-10-23 11:30:45     admin@example.com       1h0m15s
1003    ghi54321...     2023-10-23 12:00:12     support@example.com     30m48s
```

## 設定

### バッチサイズ

クレーム時のバッチサイズは `VERBENA_IN_BATCHES_OF` 環境変数で制御できます：

```bash
# .envファイル例
VERBENA_IN_BATCHES_OF=100  # 配送処理時のデフォルトバッチサイズ
```

クレーム操作時はデフォルトで小さめ（20件）ですが、環境変数で上書き可能です。

### リトライ設定

リトライロジックは指数バックオフ＋ジッターで実装：

- **最大リトライ回数**: `VERBENA_CLAIM_MAX_RETRIES`（デフォルト5）で設定
- **バックオフ戦略**: `base * 2^retry_count`（上限cap、ジッターあり、デフォルトbase=1秒, cap=300秒）
- **例外処理**: `ActiveRecord::Deadlocked`, `ActiveRecord::LockWaitTimeout`

## デプロイ手順

### 1. マイグレーション適用

```bash
rails db:migrate
```

### 2. スタッククリーンアップ用cron登録

crontabやデプロイ管理ツールに追加：

```bash
# 30分ごとに1時間以上前のスタッククレームを解放
*/30 * * * * cd /path/to/verbena && bin/rails verbena:claim:release_stale[1] >> log/stale_cleanup.log 2>&1
```

### 3. モニタリング

詰まり検知用の監視設定例：

```bash
# 毎日9時に長時間クレームをチェック
0 9 * * * cd /path/to/verbena && bin/rails verbena:claim:show_stale >> log/stale_monitoring.log 2>&1
```

## テスト

### ユニットテスト

本実装には以下の観点のテストが含まれます：

- **基本動作**: 既存のクレーム動作が維持されているか
- **並行安全性**: 複数セッションで同一レコードが重複クレームされない
- **バッチ処理**: 大量レコードが分割処理される
- **スタック解放**: 古いクレームが正しく解放される
- **エッジケース**: デッドロック回復、空集合時の動作

### テスト例

```ruby
it '同一レコードが重複クレームされない（基本的な排他制御テスト）' do
  session_id_1 = MailQueue.issue_session_id
  session_id_2 = MailQueue.issue_session_id

  # 1つ目のセッションでクレーム
  claimed_count_1 = MailQueue.claim_by_timer!(session_id_1)

  # 2つ目のセッションでクレーム（残りがあれば取得）
  claimed_count_2 = MailQueue.claim_by_timer!(session_id_2)

  # 合計が元のレコード数と一致する
  expect(claimed_count_1 + claimed_count_2).to eq(available_records.length)

  # それぞれのセッションで取得したレコードに重複がない
  session_1_ids = MailQueue.claimed(session_id_1).pluck(:id)
  session_2_ids = MailQueue.claimed(session_id_2).pluck(:id)
  expect(session_1_ids & session_2_ids).to be_empty
end
```

## パフォーマンス考慮

### MySQL最適化

- **小バッチ**: ロック時間・競合を低減
- **効率的なインデックス**: クレーム操作の高速化
- **LIMIT句**: フルスキャン防止
- **WHERE条件**: インデックス活用

### 本番運用の推奨

1. **デッドロック頻度の監視**: 少なければバッチサイズ増加も検討
2. **スタックタイムアウト調整**: 回復速度と誤検知のバランス
3. **DBコネクション数**: 並行クレームに十分なプールを確保
4. **ログ監視**: クレーム操作のパフォーマンスを定期確認

## 旧実装からの移行

新実装は **後方互換** です：

- **既存動作維持**: すべての公開APIはそのまま動作
- **段階的導入**: 呼び出し側の変更不要
- **パフォーマンス向上**: デッドロック減少・スループット向上
- **自動回復**: スタックレコードは自動的に回復

### 破壊的変更: なし

API互換性を維持しつつ、内部実装の堅牢性を向上しています。

## トラブルシューティング

### よくある問題

1. **デッドロック頻発**
   - **原因**: バッチサイズが大きすぎる or 並行度が高すぎる
   - **対策**: `VERBENA_IN_BATCHES_OF` を減らす、実行タイミングをずらす

2. **スタックレコードが溜まる**
   - **原因**: cron未実行 or タイムアウトが長すぎる
   - **対策**: cron設定確認、タイムアウト短縮

3. **クレーム操作が遅い**
   - **原因**: インデックス不足 or バッチサイズが大きすぎる
   - **対策**: インデックス確認、バッチサイズ縮小

### デバッグコマンド

```bash
# 現在のクレーム済みレコード数
rails runner "puts MailQueue.where.not(session_id: nil).count"

# スタックレコード数
rails runner "puts MailQueue.where('claimed_at < ?', 1.hour.ago).count"

# 手動スタック解放（ドライラン）
rails verbena:claim:release_stale[1,dry]
```
