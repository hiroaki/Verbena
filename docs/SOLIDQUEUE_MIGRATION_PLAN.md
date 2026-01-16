# Verbena v1.0 Refactoring Plan: SolidQueue Migration

このドキュメントは、Verbena を現在の「Rakeタスク駆動型（v0.9）」から「SolidQueue駆動型（v1.0）」へ移行するための改修計画書です。
次のAIセッションでは、このドキュメントに基づき開発を進めてください。

## 1. 背景とねらい

### 現状 (v0.9) の課題
現在の Verbena は、メール配送の実行を `cron` 等の外部スケジューラによる Rake タスクの定期実行に依存しています。
- **即時性の欠如**: ポーリング間隔（例: 1分）での配送となります。
- **設定の煩雑さ**: ユーザーは Docker コンテナ起動に加え、適切な cron 設定を行う必要があります。
- **再送ロジックの複雑さ**: 独自実装の `claim!` メカニズムで排他制御を行なっていますが、メンテナンスコストが高い状態です。

### 目指す姿 (v1.0)
Rails 7.1+ 標準の **SolidQueue** を採用し、アプリケーション自身が自律的にジョブを処理する構成へ移行します。
- **DB中心設計の維持**: オンプレミス環境での運用を考慮し、Redis を必要とする Sidekiq は採用しません。DBのみで完結する SolidQueue が最適です。
- **「ゲートウェイ」としての責務**: アプリケーションプロセスを起動するだけで、配送・再送・スケジュール実行が完結するようにします。

## 2. 実装方針と制約・詳細仕様

- **フレームワーク要件**:
  - Ruby on Rails 7.1+ (現在の Gemfile は `~> 7.1` なので要件を満たしています)
- **インフラ**: Redis は使用しない。DBのみで完結する SolidQueue が最適です。
- **コンテナ構成**: Webサーバプロセスに加え、Workerプロセスを管理する必要があります。

### 詳細仕様決定事項

#### A. ジョブ粒度とバッチ処理
- **1ジョブ = 1 MailQueueレコード（1宛先）** とします。
- 現在の `in_batches_of` は「DBロック競合低減」が主目的だったため、SolidQueue 移行により不要となります。
- SMTP接続の再利用（Bulk送信）は v1.0 ではスコープ外とし、まずは単純な `perform_later` での移行を優先します。

#### B. `timer_at` の扱い
- **カラムは保持します**。API仕様としての「予約日時」およびビジネスデータとしての正としての役割を残すためです。
- 実装: `MailQueuesService` は `timer_at` が存在する場合、`DeliveryJob.set(wait_until: mail_queue.timer_at).perform_later(mail_queue)` としてエンキューします。
- SolidQueue 側の `scheduled_at` が実際の実行制御を行いますが、`mail_queues.timer_at` は参照用として残ります。

#### C. リトライ戦略
- **ActiveJob の `retry_on` を使用します**。
- **対象エラー**: ネットワークエラー (`Net::OpenTimeout` 等) および SMTP 4xx エラー（一時エラー）。
- **リトライ回数**: 既存設定 `VERBENA_CLAIM_MAX_RETRIES` (既定5) に準じ、`attempts: 5` 程度を設定。
- **待機時間**: `wait: :exponentially_longer` (指数バックオフ) を使用。
- **5xx エラー**: リトライせず、即座に失敗として `DeliveryResponse` に記録します。

#### D. 既存・移行中データの扱い
- **移行スクリプトを用意します**。
- デプロイ直後に実行する Rake タスク (`verbena:migrate:enqueue_pending`) を作成します。
- 対象: `session_id: nil` かつ `delivery_responses` が無い過去のレコード全てを対象に、`DeliveryJob` をエンキューします。

#### E. DeliveryService の変更点
- **現在の並列処理ロジック (`Parallel.each`) は削除します**。ジョブシステムが並列実行を担当するため不要です。
- `DeliveryService#perform_one(mail_queue)` メソッドはそのまま維持します。
- **エラーハンドリングの変更**: 
  - 現在は例外をキャッチして `DeliveryResponse` に記録していますが、Job移行後は以下のように変更します：
    - **4xx / ネットワークエラー**: `DeliveryResponse` にエラー詳細を記録（commit）した上で、例外を raise して Job のリトライに任せる（※試行履歴を残すため）
    - **5xx エラー**: 例外を raise せず、`DeliveryResponse` に記録して正常終了
    - **成功 (2xx)**: `DeliveryResponse` に記録して正常終了

#### F. 環境変数の整理
- 以下の環境変数は廃止となります（Issue 5で設定参照コードを削除）:
  - `VERBENA_IN_BATCHES_OF` (バッチ処理廃止のため)
  - `VERBENA_CLAIM_MAX_RETRIES` (ActiveJobのリトライ設定に置き換え)
  - `VERBENA_CLAIM_BACKOFF_*` (ActiveJobのリトライ設定に置き換え)
  - `VERBENA_PARALLEL_*` (並列処理廃止のため)
- `docs/ENVIRONMENT_VARIABLES.md` の更新も Issue 7 に含めます。

## 3. 具体的な改修タスク (Issues)

次の順序で開発を進めてください。

### Issue 1: SolidQueue の導入と基盤設定
- **目的**: アプリケーション内で SolidQueue が動作する環境を作る
- **タスク**:
  - `Gemfile` に `solid_queue` を追加し `bundle install`。
  - `bin/rails solid_queue:install:migrations` および `db:migrate`。
  - `config/queue.yml` の作成（配送用 queue の定義）。
  - `config/environments/*.rb` で `config.active_job.queue_adapter = :solid_queue` を設定。
  - `spec/spec_helper.rb` または `rails_helper.rb` に ActiveJob テストヘルパーの設定を追加（`include ActiveJob::TestHelper`）。

### Issue 2: DeliveryJob の実装とロジック移管
- **目的**: Rakeタスクで行っていた配送処理を ActiveJob に移植する
- **タスク**:
  - `app/jobs/delivery_job.rb` を作成。引数には `mail_queue_id` (Integer) を取る（モデルインスタンスではなくIDを渡す）。
  - Job内で `MailQueue.find(mail_queue_id)` して取得。
  - `DeliveryService` を修正:
    - 並列処理ロジック (`Parallel.each`) を削除
    - `#perform_one` で4xxエラーやネットワークエラーが発生した場合は、**ログ(`DeliveryResponse`)を記録した上で** `raise` し、Jobのリトライに任せる
    - 5xxエラーは `DeliveryResponse` に記録し、例外を raise しない（Job成功扱い）
  - Jobクラスに `retry_on Net::SMTPServerBusy, wait: :exponentially_longer, attempts: 5` などを記述。
  - テスト: Job実行とリトライのスペックを追加。

### Issue 3: Ingest処理 (MailQueuesService) の変更
- **目的**: EML受信時に、DB保存だけでなくジョブをエンキューするようにする
- **タスク**:
  - `MailQueuesService` で `MailQueue` レコード保存後の処理を以下に変更:
    ```ruby
    if mail_queue.timer_at.present? && mail_queue.timer_at > Time.current
      DeliveryJob.set(wait_until: mail_queue.timer_at).perform_later(mail_queue.id)
    else
      DeliveryJob.perform_later(mail_queue.id)
    end
    ```
  - テストコード: ジョブがエンキューされたことを検証するスペックを追加（即時 / 遅延の両パターン）。

### Issue 4: 移行用 Rake タスクの作成 (データ移行)
- **目的**: アップデート時に、旧システムに残っている未処理データをジョブに乗せる
- **タスク**:
  - Rakeタスク `verbena:migrate:enqueue_pending` を作成。
  - 条件: `session_id` が NULL または 古いタイムスタンプを持ち、かつ `delivery_responses` が存在しないレコード。
  - これらをループして `DeliveryJob.perform_later` する。
  - **注意**: このタスクはリリース後のデータ移行手順としてドキュメント化する。

### Issue 5: モデルのリファクタリング (脱・独自Claim)
- **目的**: 不要になった独自排他制御ロジックを削除する
- **タスク**:
  - `MailQueue` モデルから `claim!` メソッド、`session_id`, `claimed_at` 関連のロジック、および `VERBENA_IN_BATCHES_OF` などのバッチ設定参照を削除。
  - テーブル定義からは、後方互換性のためカラム自体は一旦残す（削除マイグレーションは作成しない）。

### Issue 6: コンテナ起動スクリプトの修正
- **目的**: `docker compose up` だけで Web と Worker が動くようにする
- **タスク**:
  - `Procfile` または `entrypoint.sh` を修正し、Rails Server と SolidQueue Worker が起動するようにする。
  - 開発環境(`compose.yml`)では `bin/jobs` (SolidQueue 付属コマンド等) を追加で起動する設定にするか、Rails 8 ライクな振る舞いを模倣する。

### Issue 7: 不要な Rake タスクとドキュメントの整理
- **目的**: 古い実行方法を廃止する
- **タスク**:
  - `lib/tasks/verbena/delivery.rake` 内の `by_timer`, `by_ids` タスクを削除。
  - `lib/tasks/verbena/claim.rake` 全体を削除（claim機構廃止のため）。
  - **注意**: `prepare_retry` や `reset_undelivered` など、手動再送用タスクは**残す**（運用上のトラブルシューティングツールとして必要）。ただし実装は `MailQueue` の claim ロジックではなく、ジョブの再エンキューに変更する。
  - `README.md` を更新:
    - 「cron設定は不要」と明記
    - 「メール配送」セクションを「アプリ起動で自動的に処理される」旨に書き換え
    - 「確保/再送」セクションは手動再送タスクの説明のみ残す
  - `docs/ENVIRONMENT_VARIABLES.md` から廃止された環境変数を削除。

## 4. 次期セッションへの申し送り

このファイルをコンテキストとして読み込み、**Issue 1** から順に着手してください。
Issue 1 が完了したら、動作確認（ジョブテーブルが作成されているか等）を行い、Issue 2 へ進んでください。
