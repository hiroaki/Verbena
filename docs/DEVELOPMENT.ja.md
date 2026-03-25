# Verbena 開発ガイド

このドキュメントは Verbena の開発者向けの情報をまとめています。環境構築、テスト、アーキテクチャ設計、技術的な意思決定の背景などを記載しています。

## 目次

- [開発環境のセットアップ](#開発環境のセットアップ)
- [デプロイ](#デプロイ)
- [I18n / ロケール](#i18n--ロケール)
- [テスト](#テスト)
- [アーキテクチャ](#アーキテクチャ)
- [データベース設計](#データベース設計)
- [トークン運用ルール](#トークン運用ルール)

---

## 開発環境のセットアップ

### 前提条件

- Docker と Docker Compose
- Git


### 初回セットアップ

1. **リポジトリのクローン**

```sh
$ git clone https://github.com/hiroaki/Verbena.git
$ cd Verbena
$ git checkout develop
```

2. **環境変数の設定**

※ コンテナ起動前に「データベース初期化用の環境変数」の設定が必要です。詳細は後述セクション（「データベース初期化用の環境変数」）を参照してください。

環境変数は `.env` ファイル、`compose.yml`、各種 `compose.*.yml` などで管理できます。

`.env` ファイルは必須ではありません。必要に応じて外部ファイルで管理したい場合のみ、以下のように作成・編集してください。

```sh
$ cp dot.env.sample .env
```

`.env` ファイルを使わず、`compose.yml` や各種 `compose.*.yml` に直接環境変数を記載している場合は `.env` は不要です。ご自身の運用に合わせて選択してください。

3. **データベースの選択**

Verbena の Docker Compose 構成は「共通 (compose.yml) + DB オーバーレイ」を組み合わせて利用します。使用したいデータベースに合わせて、以下のようにファイルを指定してください。

```sh
# MySQL / MariaDB
$ docker compose -f compose.yml -f compose.mysql.yml up -d

# PostgreSQL
$ docker compose -f compose.yml -f compose.postgresql.yml up -d

# SQLite (DB サービスは不要)
$ docker compose -f compose.yml -f compose.sqlite.yml up -d
```

以降のコマンド例では MySQL オーバーレイ（`compose.mysql.yml`）を使用しています。PostgreSQL や SQLite を利用する場合は、適宜ファイル名を読み替えてください。

4. **コンテナのビルドと起動**

```sh
$ docker compose -f compose.yml -f compose.mysql.yml build
$ docker compose -f compose.yml -f compose.mysql.yml up -d
```

5. **データベースの初期化**

```sh
$ docker compose -f compose.yml -f compose.mysql.yml exec web rails db:prepare
```

### データベース初期化用の環境変数

初回起動時、データベースコンテナは `./initdb` 配下のスクリプトを自動実行してデータベースユーザーの権限を設定します。

#### MySQL / MariaDB

以下の環境変数が必要です（`.env` または `compose.mysql.yml` で指定）：

| 変数名               | 説明 |
|----------------------|------|
| `MYSQL_ROOT_PASSWORD`| MySQL rootユーザーのパスワード。初期化スクリプト用。必須。 |
| `MYSQL_USER`         | アプリ用DBユーザー名。必須。 |
| `MYSQL_PASSWORD`     | アプリ用DBユーザーパスワード。必須。 |
| `DATABASE_NAME`      | データベース名のベース。既定値: `verbena` |

`.env` で `DATABASE_NAME` を指定すると、その値をベース名として開発用 DB を `${DATABASE_NAME}_development` という規約で自動作成します。

#### PostgreSQL

以下の環境変数を利用します（未設定時は表のデフォルト値を使用）：

| 変数名 | 説明 |
|--------|------|
| `POSTGRES_USER` | PostgreSQL スーパーユーザー名。既定: `postgres` |
| `POSTGRES_PASSWORD` | 上記スーパーユーザーのパスワード。既定: `postgres` |
| `VERBENA_DATABASE_USER` | Rails アプリ用の DB ユーザー名。既定: `POSTGRES_USER` と同じ |
| `VERBENA_DATABASE_PASSWORD` | 上記アプリ用ユーザーのパスワード。既定: `POSTGRES_PASSWORD` と同じ |
| `DATABASE_NAME` | データベース名のベース。既定値: `verbena` |

特に指定しない場合、アプリケーションユーザーと PostgreSQL スーパーユーザーは同じ資格情報になりますが、セキュリティ要件に応じて別々の値を設定できます。

#### SQLite

SQLite はファイルベースのため、DB サーバ用の環境変数は不要です。`storage/` ディレクトリに自動的にファイルが作成されます。

#### 注意事項

- ボリュームに既存のデータがある場合は初期化スクリプトが実行されません
- 完全に初期状態へ戻す場合はボリュームを削除し、再作成してください

---

## デプロイ

本プロジェクトでは Kamal + dotenv を利用したデプロイ方法を提供します。

### 構成

TODO

### 関連ファイルの役割

| ファイル | 役割 | 備考 |
|---|---|---|
| `config/deploy.yml` | Kamal 共通設定 | 環境共通のベース定義 |
| `config/deploy.staging.yml` | staging 固有設定 | サーバー、アクセサリ、env を定義 |
| `.kamal/secrets.staging` | staging の secret マッピング | 値本体は環境変数から参照 |
| `dot.env.staging.sample` | dotenv テンプレート | 実運用時は `.env.staging` を作成して使用 |

### 事前準備

設定はすべて環境変数で行います。変数の数が多いため dotenv を利用してください。

テンプレートが用意されていますので、これを複製したうえで編集します。

```sh
$ cp -i dot.env.staging.sample .env.staging
```

### デプロイ手順（staging）

事故防止のため `require_destination: true` を有効化しており、 kamal コマンドの実行時には `-d staging` の指定が必須です。

```sh
# 現在の設定を確認
$ dotenv -f .env.staging -- kamal config -d staging

# DBアクセサリ起動（初回 / 再作成時）
$ dotenv -f .env.staging -- kamal accessory boot mysql -d staging

# アプリ本体デプロイ
$ dotenv -f .env.staging -- kamal deploy -d staging

# ログ確認
$ dotenv -f .env.staging -- kamal app logs -d staging
```

## I18n / ロケール

Verbena は日本語 (ja) / 英語 (en) の 2 言語に対応します。既定は英語です。

- 既定ロケール: `en`
- フォールバック: `ja -> en`
- 設定場所: `config/application.rb`
- ロケールファイル: `config/locales/*.yml`
- 標準翻訳: `rails-i18n` gem を利用

### 追加・更新の方針

- 画面文言は `t("...")` を利用し、`config/locales/en.yml` と `config/locales/ja.yml` の両方にキーを追加します。
- モデル名/属性名/エラーメッセージは `activerecord.*` 配下に整理します。
- API メッセージは英語固定の方針です。

---

## テスト

### テストの実行

テストは RSpec を利用しています：

```sh
# 全テストを実行
$ docker compose -f compose.yml -f compose.mysql.yml exec web bundle exec rspec

# 特定ファイルだけ実行
$ docker compose -f compose.yml -f compose.mysql.yml exec web bundle exec rspec spec/tasks/verbena/mail_queues_rake_spec.rb

# 特定の行だけ実行
$ docker compose -f compose.yml -f compose.mysql.yml exec web bundle exec rspec spec/models/mail_queue_spec.rb:42
```

### カバレッジレポート

テストを実行すると `coverage` ディレクトリにカバレッジレポートが出力されます：

```sh
$ open coverage/index.html
```

---

## アーキテクチャ

### システムの責務範囲

#### 配送のスコープ

Verbena は **SMTP 配送先サーバへの引き渡しまで** を担当します。

- **担当する範囲**: アプリケーションから配送先SMTPサーバへのメール配信が成功したこと（SMTP応答 `250 OK` の受信）
- **担当しない範囲**:
  - リレー先サーバでの配送失敗（バウンス）
  - スパムフィルタによるブロック
  - 最終的な受信箱への到達
  - ユーザーによる開封・閲覧

この責務範囲の定義は、SMTP プロトコルの技術的特性に基づいています：

- SMTP の「250 OK」応答は、そのサーバがメールを受理したことのみを意味します
- その後のリレーや最終配送での失敗は、即時には検知できません
- 後続のバウンスは通常「バウンスメール（DSN）」として送信元に返送されます

SMTP プロトコルの仕様上、配送先サーバが `250 OK` を返した時点で「受理した」ことのみが確認できます。その後のリレーや最終的な受信箱への到達、バウンス発生については、配送元から即時に把握する手段はありません。

また、バウンス（配信不能通知）は配送先サーバが後から送信元に返す仕組みであり、非同期かつ必ずしも返送されるとは限りません。そのため、リアルタイムな到達確認や再送制御は SMTP の標準的な仕組みでは実現されていません。

### 設計原則

#### 1. 並行処理の安全性

- **SolidQueue** を採用し、標準的な非同期ジョブ基盤上でスケーラブルな並行処理を実現
- `DeliveryJob` によるジョブ単位での安定した配送実行
- ジョブのリトライ機構を利用した堅牢なエラーハンドリング

#### 2. 追跡可能性

- すべての配送試行を `DeliveryResponse` に記録
- 構造化ログによる配送プロセスの可視化
- `Message-ID` によるメール追跡

#### 3. 柔軟な配送制御

- タイマーベース配送（遅延配信）：`ScheduledDeliveryJob` によるポーリングとエンキュー
- 4xxステータスの再送管理：エラー時の再送処理による自動リカバリ
- バッチサイズ・並行数の調整可能

#### 4. 運用容易性

- Docker環境での完結した開発・テスト
- Rakeタスクによる日常運用
- 設定の環境変数管理

### システム構成

#### コアモデル

Verbena のコアモデルは、メール配送処理の各段階を明確に分離して管理します。

- **EmlSource**: 受信した EML ファイル（生メールデータ）を保存します。1通の EML につき1レコード。添付ファイルやヘッダ情報も含め、元のメール内容をそのまま保持します。

- **MailQueue**: 配送対象ごと（受信者ごと）に配送キューを生成します。1つの EML から複数の MailQueue が作成されることもあります（例: 複数受信者への同報送信）。配送予定時刻やステータス、リトライ回数などの管理も行います。

- **DeliveryResponse**: 各配送試行の結果を記録します。SMTP サーバへの配送ごとに1レコードが作成され、応答内容（例: 250 OK やエラーコード）、配送日時、リトライ情報などを保持します。

モデル間の関係は以下の通りです：

```
EmlSource (生EML保存)
  └─<1対多>─> MailQueue (配送キュー、受信者ごと)
      └─<1対多>─> DeliveryResponse (配送結果)
```

この構造により、1通のメール（EML）から複数受信者への個別配送、各配送のリトライや結果追跡が柔軟に行えます。

#### 配送フロー

Verbena の配送フローは、EML ファイルの受信から配送完了・後処理まで、以下の段階で構成されています。

1. **Ingest（取り込み）**
  - ユーザーや外部システムから EML ファイル（生メールデータ）がアップロードまたは投入されます。
  - `MailQueuesService` が EML を解析し、宛先ごとに `MailQueue` レコードを生成します。
  - これにより、1通のメールから複数受信者への個別配送が可能になります。

2. **Scheduling（配送スケジューリング）**
  - 各 `MailQueue` には配送予定時刻や即時配送フラグが設定されます。
  - 即時配送の場合は、`MailQueue` 作成直後に `DeliveryJob` がエンキューされます。
  - 予約配送の場合は、`ScheduledDeliveryJob` が定期的に実行され、配送予定時刻に達したキューを検知して `DeliveryJob` をエンキューします。
  - これにより、遅延配信やバッチ配送など柔軟なスケジューリングが可能です。

3. **Deliver（配送実行）**
  - `DeliveryJob` がキューごとに起動し、`DeliveryService` を通じて SMTP サーバへの配送処理を行います。
  - 配送の成否や SMTP 応答内容は `DeliveryResponse` に記録されます。
  - エラー発生時はリトライ制御も行われ、再配送が必要な場合は再度ジョブがエンキューされます。

4. **Cleanup（後処理・クリーンアップ）**
  - 配送が完了した `MailQueue` や、参照されなくなった `EmlSource` の削除（クリーンアップ）は、ユーザーが任意のタイミングで Rake タスク（例: `verbena:cleanup:weekly` など）を実行することで行います。
  - 定期的な自動実行は標準では設定されていません。必要に応じて cron 等でスケジューリングしてください。


この一連のフローにより、EML の受信から多宛先への個別配送、配送結果の記録までを自動化し、データ保持・削除の運用は利用者の裁量に委ねています。

#### メールデータ入力の仕組み

Verbena では、配送対象となるメールデータ（EML形式）は `eml_sources` テーブルに保存されます。それと同時に EMLのヘッダ `To:` `Cc:` `Bcc:` に記載された各宛先ごとに、配送キューとして `mail_queues` テーブルのレコードが作成されます（重複は除外）。

##### 入力方法

- Rakeタスク経由: EMLファイルのパスを指定して `verbena:mail_queues:add` を実行
- Web API経由: EMLデータをPOST（`Authorization`ヘッダにトークン必須）

いずれの場合も、EMLの宛先ヘッダに基づき複数の `mail_queues` レコードが生成されます。

例：

```sh
Date: Tue, 1 Jul 2003 10:52:37 +0200
From: me@example.com
To: you@example.com
Cc: ichiro@example.com, jirou@example.com
Bcc: saburo@example.com
Subject: ...
Content-Type: text/plain; charset="UTF-8"

こんにちは。
```

この場合、4件の `mail_queues` レコードが作成されます。

各レコードの違いは、実際の送信先となるメールアドレスが格納される `envelope_to` カラムのみです。配送処理は `mail_queues` の各レコード単位で行われ、EMLのヘッダ上の複数宛先情報は関係なく、`envelope_to` の宛先にのみ送信されます。

また、EMLのヘッダ `Date:` の値は「配送予約時刻」として `mail_queues` テーブルの `timer_at` カラムに格納されます。`Date:` が省略された場合は、`timer_at` には現在時刻が設定されます。


### 将来の拡張計画

#### バウンス管理機能（次期マイルストーン）

配送後のバウンスを管理することで、実質的な到達性を向上させます。
詳細は [BOUNCE_MANAGEMENT.ja.md](BOUNCE_MANAGEMENT.ja.md) を参照してください。

#### 想定される拡張機能

- 配信速度制御（レート制限）
- 宛先ドメインごとの同時接続数制限
- DKIM署名サポート
- 配信統計ダッシュボード
- Webhook通知

---

## データベース設計

### 対応データベース

Verbena は複数のデータベースシステムをサポートします：

| Database | Version | Status |
|----------|---------|--------|
| MySQL    | 8.0+    | ✅ Supported |
| MariaDB  | 10.6+   | ✅ Supported |
| PostgreSQL | 13+   | ✅ Supported |
| SQLite   | 3.x     | ✅ Supported |

### マイグレーションの互換性

すべてのマイグレーション（`db/migrate/`）は、以下の原則に従い、複数のデータベースで動作するように設計されています：

- **MySQL 専用オプション（`after:`、`charset:`、`collation:`）は使用しない**: MySQL 固有の `after:` などでカラム並び順を制御・前提とせず、実際の並び順は各データベース実装に依存するものとして、ポータブルな Rails マイグレーション構文を採用
- **型固有のオプションはアダプタ非依存**: `:text` 型に対する MySQL 固有のサイズ指定オプション（`limit:` など）のように、DB ごとに挙動が異なる指定は使わず、すべての DB で解釈可能なプレーンな型指定のみを使用
- **SQL の直接記述を避ける**: `execute()` 句でベンダー固有の SQL を使わないよう注意

### スキーマの更新

マイグレーションを追加・変更した場合は、各DB環境で `bin/rails db:schema:dump` を実行し、対応するスキーマファイルを最新化してください。

| DATABASE_ADAPTER | スキーマ・ファイル          |
|------------------|--------------------------|
| mysql2           | db/schema.mysql2.rb      |
| postgresql       | db/schema.postgresql.rb  |
| sqlite3          | db/schema.sqlite3.rb     |

データベース・スキーマは、コンテナ起動時の `entrypoint.sh` により、DATABASE_ADAPTER に対応するスキーマ・ファイルが `db/schema.rb` として配置されます。したがって `db/schema.rb` ファイルはバージョン管理から除外されています。

### タイムゾーン方針 (UTC)

Verbena は一貫して UTC で動作するように設計されています：

- **Rails アプリケーション**: 常に UTC で動作（`config.time_zone = 'UTC'`）
- **データベース OS**: タイムゾーンを UTC（`TZ=UTC`）に固定
- **MySQL/MariaDB**: `config/database.yml` で `init_command: "SET time_zone = '+00:00'"` を指定し、セッションのタイムゾーンを UTC に固定
- **PostgreSQL**: `config/database.yml` で `variables: { timezone: 'UTC' }` を指定し、セッションタイムゾーンを UTC に固定
- **SQLite**: セッション／データベースのタイムゾーン設定はなし。日時は Rails 側で UTC として生成・管理

### プログラミングガイドライン

- DB内の `NOW()` や `CURRENT_TIMESTAMP` などのタイムゾーンが影響する関数は使わず、Rails で生成した日時値をバインドして利用してください
- 日時は常に UTC として扱い、表示時のみユーザーのタイムゾーンに変換します

### EML データの保存方針

EML (Raw email format) は `eml_sources.eml` カラムに保存されます。

#### 現在の方針（互換性優先）

- データベースに保存する EML は plain `:text` 型を使用し、すべてのデータベースで互換性を確保しています
- MySQL の `TEXT` 型は約 64 KiB、PostgreSQL と SQLite の `text` は事実上無制限です
- 添付ファイルがない、または小さいメール（通常のビジネスメール）であれば、この制限内で対応可能です

#### 将来の拡張計画（オブジェクトストレージ対応予定）

- より大きな EML ファイル（大きな添付ファイル付き）をサポートするために、オブジェクトストレージの利用を検討しています
- その際は、EML 本体をストレージに保存し、DB にはメタデータと小さなプレビューのみを保持します

## トークン運用ルール

Verbena のメールデータ入力（Rake/Web API）には Bearer トークン認証が必要です。トークン管理・運用上の注意点は以下の通りです。

- トークンの発行・更新は管理者のみが行います。利用者は配布された `key` のみ使用し、作成や更新はできません。
- 発行時はモデルのファクトリメソッド `Token.create_unique!` を使用してください。
- `key` の値は機密情報です。対象利用者以外に見られないよう保護してください。
- `label` は利用者の目印としてユニークな値を設定します。
- 有効期限は `expires_at` に設定し、その時刻まで有効です（必須）。
- 無効化は物理削除ではなく `revoked_at` をセットすることで行ってください（監査のため）。
- 発行後の `key` の更新は禁止されています（UNIQUE制約違反時に他人のkeyの存在が推測できるため、セキュリティ上の理由です）。変更が必要な場合は既存トークンを `revoke!` して無効化し、新しいトークンを作成してください。
- 期限切れトークンの一括無効化は Rake タスク `verbena:tokens:revoke_expired` を利用してください。

作成例：

```ruby
Token.create_unique!(label: "hoge", key: "user-secret", expires_at: 1.year.from_now)
```

期限切れトークンの無効化：

```sh
# ドライラン（何件無効化されるかを確認）
$ bundle exec rake verbena:tokens:revoke_expired[dry]

# 実行（expires_at を過ぎ、まだ revoked されていないトークンを revoked にする）
$ bundle exec rake verbena:tokens:revoke_expired
```
