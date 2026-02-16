# Verbena

Verbena は、複数のクライアントアプリケーションから EML 形式のメールを受け取り、外部 SMTP サーバへの配送と結果記録を一元管理する**メール配送ゲートウェイ**です。

## 目的

Verbena は各クライアントの「メールを配送する」責務を分離するための独立したアプリケーションです。クライアントは EML を Verbena に渡すだけで、配送の実行・記録・再試行を Verbena 側に委譲できます。

ただし SMTP サーバへの引き渡しまでを責務としており、最終的な受信箱への到達やバウンス管理は対象外です。

**解決する課題：**

- クライアントごとに実装・運用している外部 SMTP との通信や失敗時の取り扱いを一元化したい
- 複数宛先への送信で一部が失敗した場合、失敗した宛先だけを正確に把握して再送したい

**提供する機能：**

- **配送責務の分離**: クライアントは EML を渡すだけ。配送・再送・記録は Verbena が担当
- **宛先単位の管理**: 複数宛先への送信を個別に記録し、失敗した宛先のみ再送可能
- **自動再送**: 一時エラー時の再送をバックグラウンドジョブで自動処理
- **配送予約**: 指定時刻まで配送を待機

## 準備

### 1. トークンの作成

EML登録（Rake/Web API）には Bearer トークン認証が必要です。管理者が利用者ごとにトークンを発行します：

```ruby
Token.create_unique!(label: "client-name", key: "secret-key", expires_at: 1.year.from_now)
```


**運用上の注意:**
- トークンの発行・更新は管理者のみが行います。利用者は配布された `key` のみ使用し、作成や更新はできません。
- 発行後の `key` の更新は禁止されています。変更が必要な場合は既存トークンを `revoke!` して無効化し、新しいトークンを作成してください。
- 期限切れトークンの一括無効化は Rake タスク `verbena:tokens:revoke_expired` を利用してください。

### 2. 環境変数の設定

主要な設定項目：

| 変数名 | 説明 | 既定値 |
|--------|------|--------|
| `VERBENA_DELIVERY_METHOD` | 配送方式 (smtp/test/file) | test (開発) / smtp (本番) |
| `VERBENA_DELIVERY_SMTP_ADDRESS` | SMTP サーバアドレス | - |
| `VERBENA_DELIVERY_SMTP_PORT` | SMTP ポート | - |
| `VERBENA_DELIVERY_SMTP_USER_NAME` | SMTP 認証ユーザ | - |
| `VERBENA_DELIVERY_SMTP_PASSWORD` | SMTP 認証パスワード | - |

全項目は [docs/ENVIRONMENT_VARIABLES.md](docs/ENVIRONMENT_VARIABLES.md) を参照してください。


## 使い方

### サーバーの起動

Verbena を起動するには以下のコマンドを実行します：

```sh
$ bin/dev
```

このコマンドで Rails サーバーと配送処理のためのバックグラウンドジョブプロセスが同時に起動します。

### メール入力

EML 形式のメールはそのまま `eml_sources` テーブルに保存され、同時に各宛先ごとに配送キュー（`mail_queues` テーブルのレコード）が作成されます。

登録方法は 2 つあります：

**Rake タスク経由**

```sh
# 環境変数でトークンを指定
$ VERBENA_TOKEN=your-secret-key bin/rails verbena:mail_queues:add[/path/to/source.eml]

# または引数でトークンを指定
$ bin/rails verbena:mail_queues:add[/path/to/source.eml,token:your-secret-key]
```

**Web API 経由**

```sh
$ curl -H 'Authorization: Bearer your-token' -X POST \
    -F 'mail_queue[eml]=@/path/to/source.eml' \
    http://localhost:23000/api/v1/mail_queues
```

EML のヘッダ `To:`, `Cc:`, `Bcc:` に記載された各宛先ごとに `mail_queues` レコードが作成されます（重複は除外）。

また、ヘッダ `Date:` の値は「配送予約時刻」として同テーブルの `timer_at` 列に格納されます。

### メール配送

配送は SolidQueue バックグラウンドジョブが自動実行します。`timer_at` が経過したレコードが順次処理され、結果は `delivery_responses` テーブルに記録されます。

開発環境では `VERBENA_DELIVERY_METHOD=test` のため実際の送信は行われません。

## ジョブ管理画面

ジョブ管理には Mission Control Jobs を利用します。Basic 認証（環境変数 `VERBENA_ADMIN_USERNAME` / `VERBENA_ADMIN_PASSWORD` で設定）が必要です。

http://localhost:23000/admin/jobs


## メンテナンス

### 古いレコードの削除

配送済みレコードは蓄積し続けるため、定期的に削除してください：

```sh
# 一週間経過したレコードを削除
$ bin/rails verbena:cleanup:weekly

# TTL（既定30日）で削除
$ VERBENA_CLEANUP_TTL_DAYS=45 bin/rails verbena:cleanup:by_ttl

# ドライラン（削除件数のみ確認）
$ bin/rails verbena:cleanup:weekly[true]
```

### 手動再送（トラブルシューティング）

通常は配送失敗時に自動で再送処理（バックグラウンドジョブによるリトライ）が行われます。
自動再送の上限を超えた場合や、管理者判断で再送したい場合は、下記の手動コマンドを利用できます。

#### 1. 4xx系一時エラーの再送

直近の配送結果が4xx系（一時的エラー）のメッセージのみを再送キューに入れます。5xx系（恒久的エラー）は対象外です。

```sh
$ bin/rails verbena:delivery:prepare_retry
```

> **注意:** 5xx系エラーは恒久的なため、復旧の前に原因を確認し、必要に応じて新しいメッセージを登録してください。

#### 2. 未配送メッセージのリセット

配送結果が1件も存在しない（24時間以上配送されていない）メッセージをリセットします。エラー種別は関係ありません。

```sh
$ bin/rails verbena:delivery:reset_undelivered
```

## 開発

### クイックスタート

```sh
# リポジトリをクローン
$ git clone https://github.com/hiroaki/Verbena.git
$ cd Verbena

# 環境変数ファイルを作成
$ cp dot.env.sample .env

# データベースを選択してコンテナを起動（MySQL の例）
$ docker compose -f compose.yml -f compose.mysql.yml build
$ docker compose -f compose.yml -f compose.mysql.yml up -d

# データベースを初期化
$ docker compose -f compose.yml -f compose.mysql.yml exec web rails db:migrate:reset

# テスト実行
$ docker compose -f compose.yml -f compose.mysql.yml exec web bundle exec rspec
```

**対応データベース**: MySQL 8.0+, MariaDB 10.6+, PostgreSQL 13+, SQLite 3.x

### 詳細ドキュメント

開発環境の詳細、アーキテクチャ設計、技術的な意思決定については以下を参照してください：

- **[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)** - 開発環境構築、テスト、アーキテクチャ、データベース設計
- **[CONTRIBUTING.md](CONTRIBUTING.md)** - 貢献ガイドライン
---

## ライセンス

This project is licensed under the 0BSD license. See [LICENSE](LICENSE).
