(Claude Sonnet 4.5 作成)
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

**A. 一時的エラーは再送、恒久的エラーはブラックリスト登録が基本方針です。**

**4xx（一時的エラー）の例**:
- 450 Mailbox full（メールボックス満杯）
- 451 Temporary local problem（一時的な問題）
- 452 Insufficient storage（サーバ側の容量不足）

→ 一定期間・回数まで再送を試みます

**5xx（恒久的エラー）の例**:
- 550 User unknown（ユーザー不明）
- 551 User not local（ユーザーが存在しない）
- 554 Message rejected（スパム判定等）

→ ブラックリストに登録し、以降の配信を停止します

## システム設計について

### Q. なぜ `UPDATE ... LIMIT` を使わないのですか？

**A. ポータビリティのためです。**

`UPDATE ... LIMIT` はMySQL/MariaDB固有の構文で、PostgreSQLでは使えません。
Verbenaでは `pluck(:id)` + `update_all` の組み合わせでバッチ更新を行い、RDBMS非依存を保っています。

詳細は [CLAIM_HARDENING.md](CLAIM_HARDENING.md) を参照してください。

### Q. なぜトランザクション内で claim しないのですか？

**A. スループットとスケーラビリティのためです。**

長時間トランザクション内でロックを保持すると、並行処理のスループットが低下します。
Verbenaでは以下の方針を採用しています：

- 短命トランザクション + 楽観的並行制御（`session_id: nil` ガード）
- デッドロック発生時は指数バックオフで再試行
- 冪等な処理により、再試行しても安全

詳細は [CLAIM_HARDENING.md](CLAIM_HARDENING.md) および [ARCHITECTURE.md](ARCHITECTURE.md) を参照してください。

### Q. 他の配信システムと連携できますか？

**A. バウンスリスト参照については、将来的にAPI公開を予定しています。**

バウンス管理機能（Phase 3）では、ブラックリストをREST API経由で参照できるようにする予定です。
これにより、Verbenaの配信機能を使わず、ブラックリスト管理だけを他システムで利用することも可能になります。

詳細は [BOUNCE_MANAGEMENT.md](BOUNCE_MANAGEMENT.md) を参照してください。

## 運用について

### Q. 大量配信時のパフォーマンスはどうですか？

**A. 並行配信数やバッチサイズを調整することで、スケールします。**

以下の環境変数で調整可能です：

```bash
# 並行配信数（Parallelライブラリ）
VERBENA_PARALLEL_IN_PROCESSES=4
VERBENA_PARALLEL_IN_THREADS=10

# バッチサイズ
VERBENA_IN_BATCHES_OF=1000
```

目安：
- 1プロセス×10スレッドで、約100通/秒
- 4プロセス並行で、約400通/秒

実際のスループットは、SMTPサーバの性能やネットワーク環境に依存します。

### Q. stale claim（処理が止まったレコード）はどうなりますか？

**A. 一定時間後に自動解放できます。**

```ruby
# 24時間以上 claimed 状態のレコードを解放
service = Verbena::MailQueuesService.new
service.release_stale_claims(older_than_hours: 24.0)

# ドライラン（件数のみ確認）
service.release_stale_claims(older_than_hours: 24.0, dry_run: true)
```

Rakeタスクも用意されています：

```bash
# stale claimを解放
rails verbena:claim:release_stale[24]

# 状況確認（解放はしない）
rails verbena:claim:show_stale
```

詳細は [CLAIM_HARDENING.md](CLAIM_HARDENING.md) を参照してください。

### Q. ログはどのように管理すれば良いですか？

**A. JSON形式の構造化ログ出力に対応しています。**

`config/initializers/log_format.rb` で `Verbena::JsonLogFormatter` を設定することで、
ログを JSON Lines 形式で出力できます。これにより、Fluentd / Logstash / CloudWatch Logs などでの集約・分析が容易になります。

```json
{"event":"deliver.result","level":"info","session_id":"20231201-120000-abc123","mail_queue_id":42,"message_id":"<xyz@example.com>","smtp_status":"250","message":"OK sending..."}
```

## トラブルシューティング

### Q. 配信が止まっているようです

**確認事項**:

1. **claim されているレコードの確認**
   ```ruby
   MailQueue.claimed('session_id').count
   ```

2. **stale claim の確認**
   ```bash
   rails verbena:claim:show_stale  # 現在 claim 中で未配送のレコードを表示
   ```

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

詳細は [README.md](README.md) の「トラブルシューティング」セクションを参照してください。
