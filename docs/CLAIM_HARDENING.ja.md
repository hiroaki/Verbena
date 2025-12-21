(Claude Sonnet 4.5 による翻訳版)
---

# MailQueue.claim! 強化実装ドキュメント

このドキュメントは、`MailQueue.claim!` の強化実装について、並行実行の安全性と自動的なスタックレコード回復の仕組みを日本語で解説します。

## 概要

従来の `claim!` メソッドは単純な `update_all` に依存しており、並行環境ではレースコンディションが発生する可能性がありました。本実装では以下の点を強化しています：

1. **アトミックなバッチ処理**: まず ID を選択し、その後 ID セットで更新することで、ロック競合を削減
2. **デッドロック回復**: 完全ジッター付き指数バックオフを実装（デフォルト: base=1秒, cap=300秒; 各試行でのランダム化による最大待機時間範囲: 0–1秒, 0–2秒, 0–4秒, 0–8秒, 0–16秒, ...）
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
2. **デッドロック時はリトライ**（完全ジッター付き指数バックオフ、`VERBENA_CLAIM_BACKOFF_BASE_SECONDS` と `VERBENA_CLAIM_BACKOFF_CAP_SECONDS` で設定可能；デフォルト: base=1秒, cap=300秒）
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

### 実装詳細: バッチクレーム戦略

#### なぜ ID 先取得方式を採用したのか？

**改修前の問題点（LIMIT + update_all パターン）**:
- `where(...).limit(n).update_all(...)` はデータベースアダプタ依存:
  - MySQL では `UPDATE ... LIMIT n` 構文で動作
  - PostgreSQL 等ではサポートされない
  - クロスデータベース互換性が失われる
- ORM レベルで LIMIT を含む update_all は期待通りに行数制限されない場合がある:
  - サイレントな挙動差（期待した件数が更新されない、または全件更新される）
  - 意図しない大量更新のリスク
- LIMIT を伴う UPDATE は DB によって最適なロック戦略が異なり、デッドロックの温床になる

**現在の方式（ID を先に取得してから ID セットで update_all）**:
1. まず小バッチ分のレコード ID を SELECT で取得（`pluck(:id)`）
2. 取得した ID に対して `WHERE id IN (...)` で `update_all` を実行

**長所**:
- **移植性**: PostgreSQL、MySQL など主要 DB アダプタで動作
- **予測可能性**: 明示的に特定の ID セットを更新するため、どのアダプタでも挙動が安定
- **検証可能性**: `update_all` の戻り値で実際に更新された行数が分かり、健全性チェックが可能

**TOCTOU とレースコンディションへの対応**:
- `pluck` と `update_all` の間に TOCTOU (time-of-check-to-time-of-use) の窓が存在
- 複数プロセスが同じ ID を `pluck` して同時に更新を試みる可能性がある
- **しかし**: `update_all` の WHERE 条件に `session_id: nil` ガードが含まれている
  - 各レコードに対して、1つのプロセスだけが `session_id` をセット可能
  - 既に他プロセスが claim 済みのレコードは更新件数にカウントされない
  - 明示的な行ロックなしで重複 claim を実質的に防止

**なぜ SELECT ... FOR UPDATE を使わないのか？**:
- SELECT ... FOR UPDATE は完全なレース防止を提供するが、トレードオフがある:
  - **パフォーマンス**: ロック保持時間が長く、スループットが低下
  - **移植性**: ロック構文とセマンティクスが DB ごとに異なる
  - **スケーラビリティ**: 高並行環境でロック待ちやデッドロックが発生しやすい
- 現在の `session_id: nil` ガード方式が実現する利点:
  - **短いロック時間**: 最小限のロック保持時間
  - **低デッドロック率**: 高並列環境でもデッドロックが発生しにくい
  - **優れたスケーラビリティ**: 高並行環境でのスループットが良好
  - **論理的排他性**: WHERE 条件による排他的更新を実現
  - **実用的バランス**: 本番運用に十分な安全性・移植性・スケーラビリティ

### スタックレコード管理

解放対象は配送結果が存在しないレコードに限定します（`delivery_responses` があるものは解放しません）。

```ruby
# スタック判定用の共通リレーション（モデル側）
relation = MailQueue.stale_claims_relation(older_than: 1.hour.ago)

# サービス経由で解放（更新件数を返す）
service = Verbena::MailQueuesService.new
changed = service.release_stale_claims # 既定は 1.0 時間

# 閾値（時間・hours）とドライラン
dry_count = service.release_stale_claims(older_than_hours: 2.0, dry_run: true)

# 備考:
# - しきい値は「以下」を含む（claimed_at <= older_than）
# - 絞り込み条件: session_id が NOT NULL かつ delivery_responses が存在しない
```

```ruby
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

- **最大再試行回数**: 環境変数 `VERBENA_CLAIM_MAX_RETRIES` で設定可能（デフォルト 5）。この値は「初回試行の後に行う再試行回数」を表します。カウンタは 0 始まりで、コードは `retries < max_retries` を用いており、再試行はちょうど `max_retries` 回まで許可されます。したがって総試行回数は `max_retries + 1`（例: 5 → 初回 1 回 + 最大 5 回の再試行 = 合計 6 回）です。
  - 注意: ログメッセージでは `attempt N/max_retries` の形式で再試行回数を表示します（例: 最初の再試行は `attempt 1/5`）。この分母は「最大再試行回数」を示しており、初回試行は含まれません。
- **バックオフ戦略**: `base * 2^retry_count` を上限 `cap` で制限。完全ジッターを適用（待機時間 = `rand * max_delay`、ただし `rand ∈ [0, 1)`）。デフォルト: base=1秒, cap=300秒。記載範囲（0–1秒, 0–2秒, ...）は各試行での最大可能待機時間であり、実際の待機時間は `[0, max_delay)` の範囲でランダムに決定されます。
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

## 最大再試行回数超過時の回復手順

クレーム操作で最大再試行回数を超えた場合（デッドロックが繰り返し発生した場合）、操作はエラーログを記録し、例外を送出します。これは、人による対応が必要な例外的な状況です。

### 推奨オペレーション対応

1. **まず、影響を受けたレコードをログに記録**: 問題となった `session_id` で更新されたレコードの ID サンプルと総件数を収集
2. **自動で即座にクリアしない**: 回復処理は自動ではなく、人の判断で実行することを想定
3. **以下の安全ポリシーで回復処理を実装**:
   - **対象の限定**: "未配送（delivery_responses が無い）かつ 十分に古い claimed_at" のレコードのみを対象
   - **ドライランの実装**: 実行前にどのレコードが影響を受けるか確認できるようにする
   - **実行ログの保存**: 誰が実行したか、何件、どの session_id かを記録

### 手動回復の例

特定のセッションでスタックしたレコードを手動で回復する必要がある場合：

```ruby
# 例: 5分以上前の未配送レコードのクレームをクリア
MailQueue.left_outer_joins(:delivery_responses)
         .where(session_id: problem_session_id)
         .where(delivery_responses: { id: nil })
         .where('claimed_at < ?', 5.minutes.ago)
         .update_all(session_id: nil, claimed_at: nil, updated_at: Time.current)
```

### 将来的な Rake タスクによる自動化

将来的な機能拡張として、rake タスクを実装できます（手動トリガー前提）：

- **タスク名例**: `verbena:claim:recover[SESSION_ID,only_undelivered,older_than,dry_run]`
- **オプション**: `--dry-run`, `only_undelivered=true/false`, `older_than=5.minutes`
- **ワークフロー**: まずドライラン結果を表示し、確認後に実行できるようにする
- **テスト**: ユニットテスト（recover メソッド）と rake タスクの統合テストを用意

### 現在の実装

現在のコードでは、エラーログのみを記録し、例外を再送出することで、回復の判断を呼び出し元（オペレーター）に委ねています：

```ruby
Rails.logger.error("[MailQueue] Max retries exceeded for claim operation for session_id=[#{session_id}]: #{e.message}")
raise
```

この設計により、人の判断が必要な重大な状況が自動的に解決されることを防ぎ、潜在的なデータ損失や不正な状態遷移を回避しています。

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
