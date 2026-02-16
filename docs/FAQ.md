(Claude Sonnet 4.5 作成、 GPT-5.2-Codex 修正)
---

# Verbena FAQ

## 配送保証について

### Q. 最終的にユーザーの受信箱に届いたか分かりますか？

**A. いいえ、Verbenaが保証するのは「配送先SMTPサーバへの引き渡しまで」です。**

SMTPプロトコルの仕様上、以下のような制約があります：

1. SMTPサーバが「250 OK」を返した時点で、そのサーバがメールを受理したことになります
2. その後のリレー先での配送や、最終的な受信箱への格納は、受け取ったサーバ側の責任です
3. リレー先でのバウンスや受信箱到達は、Verbenaからは直接検知できません

これはVerbenaに限らず、ほぼすべてのメール配信システム（商用SaaS含む）に共通する制約です。

### Q. それではユーザーに届かなくても分からないのですか？

**A. バウンス（配送失敗通知）を管理することで、実質的な到達性を高められます。**

リレー先で配送に失敗した場合、通常は「バウンスメール（DSN: Delivery Status Notification）」が Return-Path アドレスに返送されます。

Verbenaでは、次期マイルストーンとして **バウンス管理機能** の実装を計画しています：

1. バウンスメールを自動的に収集・解析（[Sisimai](https://sisimai.org/) を使用）
2. 配送不能アドレスをブラックリストに登録
3. 次回配信時に自動的に除外

詳細は [BOUNCE_MANAGEMENT.md](BOUNCE_MANAGEMENT.md) を参照してください。

### Q. メールを開封したかどうか追跡できますか？

**A. Verbenaには開封追跡機能はありません。**

メール開封の追跡には、以下のような別の仕組みが必要です：

- HTMLメール内にトラッキングピクセル（透明な1x1画像）を埋め込む
- リンククリックの計測（URLを独自のトラッキングサーバ経由に変換）

ただし、これらの方法には限界があります：

- メーラーが画像を自動表示しない設定の場合、検知できない
- プライバシー保護機能（iOS Mail Privacy Protection等）で無効化される
- 法的規制（GDPRなど）への配慮が必要

Verbenaの責務範囲は「SMTP配送管理」であり、開封追跡は対象外としています。

## バウンス管理について

### Q. バウンスはリアルタイムで検知できますか？

**A. SMTPレベルの即時エラー（4xx/5xx）は検知できますが、リレー先でのバウンスは遅延があります。**

**即時に検知できるもの**:
- 配送先SMTPサーバからの即時拒否（例: 554 Relay access denied）
- アドレス形式不正による例外（Net::SMTPSyntaxError）

**遅延して検知されるもの**:
- リレー先サーバでのバウンス（数分〜数時間後）
- スパムフィルタによるドロップ（バウンスが返らない場合も）

バウンス管理機能では、定期的（例: 毎時）にバウンスメールを収集・解析する方式を想定しています。

### Q. 一時的なエラー（4xx）と恒久的なエラー（5xx）はどう扱いますか？

**A. 将来的には「一時的エラーは再送、恒久的エラーはブラックリスト登録」が基本方針です。**

**4xx（一時的エラー）の例**:
- 450 Mailbox full（メールボックス満杯）
- 451 Temporary local problem（一時的な問題）
- 452 Insufficient storage（サーバ側の容量不足）

→ 将来的に一定期間・回数まで再送を試みます

**5xx（恒久的エラー）の例**:
- 550 User unknown（ユーザー不明）
- 551 User not local（ユーザーが存在しない）
- 554 Message rejected（スパム判定等）

→ 将来的にブラックリストへ登録し、以降の配信を停止します

## システム設計について

### Q. なぜ SolidQueue を採用したのですか？

**A. Rails標準機能であり、信頼性とメンテナンス性が高いためです。**

以前は独自のDBポーリングとロック機構（Claim機能）を実装していましたが、Rails 8 で標準搭載された SolidQueue へ移行しました。
これにより、複雑なロック管理やデッドロック対策のメンテナンスコストを削減し、標準的な非同期処理パターンを利用できるようになりました。

### Q. 他の配信システムと連携できますか？

**A. バウンスリスト参照については、将来的にAPI公開を予定しています。**

バウンス管理機能（Phase 3）では、ブラックリストをREST API経由で参照できるようにする予定です。
これにより、Verbenaの配信機能を使わず、ブラックリスト管理だけを他システムで利用することも可能になります。

詳細は [BOUNCE_MANAGEMENT.md](BOUNCE_MANAGEMENT.md) を参照してください。

## 運用について

### Q. 大量配信時のパフォーマンスはどうですか？

**A. SolidQueue のワーカー数などの並行数を調整することで、スケールします。**

以下の設定で調整可能です：

```yaml
# config/queue.yml
workers:
   - queues: "*"
      threads: 3
      processes: <%= ENV.fetch("JOB_CONCURRENCY", 1) %>
```

実際のスループットは、SMTPサーバの性能やネットワーク環境に依存します。

### Q. 処理が止まったジョブはどうなりますか？

**A. SolidQueue が管理し、失敗したジョブは `solid_queue_failed_executions` テーブルに記録されます。**

以下の手段で確認・再試行が可能です：

```ruby
# 失敗したジョブの確認
SolidQueue::FailedExecution.count
SolidQueue::FailedExecution.last.error

# 失敗したジョブの再試行
SolidQueue::FailedExecution.last.retry
```

### Q. ログはどのように管理すれば良いですか？

**A. JSON形式の構造化ログ出力に対応しています。**

環境変数 `VERBENA_LOG_FORMAT=json` を設定すると JSON Lines 形式で出力できます。
これにより、Fluentd / Logstash / CloudWatch Logs などでの集約・分析が容易になります。

```json
{"event":"deliver.result","level":"info","mail_queue_id":42,"message_id":"<xyz@example.com>","smtp_status":"250","message":"OK sending..."}
```

## トラブルシューティング

### Q. 配信が止まっているようです

**確認事項**:

1. **滞留しているジョブの確認**
   ```ruby
   SolidQueue::Job.count
   SolidQueue::ScheduledExecution.count  # 予約実行待ち
   SolidQueue::ReadyExecution.count      # 実行待ち
   SolidQueue::ClaimedExecution.count    # 実行中
   ```

2. **失敗したジョブの確認**
   ```ruby
   SolidQueue::FailedExecution.count
   ```
   エラー詳細を確認してください。

3. **ログの確認**
   ```bash
   tail -f log/production.log | grep deliver
   ```

4. **DeliveryResponse の確認**
   ```ruby
   DeliveryResponse.where('created_at > ?', 1.hour.ago).group(:status).count
   ```

### Q. Docker環境でビルドが失敗します

**よくある原因**:

1. **ネットワーク不通**: rubygems.org や Docker Hub へのアクセスが必要です
2. **DB起動待ち**: `docker compose up -d` 後、約60秒待ってから `rails db:migrate` を実行
3. **ポート競合**: ポート3000が既に使われていないか確認
