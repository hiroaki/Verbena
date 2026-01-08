# Verbena

Verbena は、クライアント（送信元アプリケーションやバッチなど）からメール送信を委譲し、外部 SMTP サーバへの送信と送信結果の記録を担当する**独立したメール配送ゲートウェイ**です。

基本的なフロー:

- クライアントが EML を生成する
- クライアントが Verbena の API に EML を送る
- Verbena が外部 SMTP サーバへ送信し、結果を宛先単位で記録する

注意: Verbena が担当するのは、外部 SMTP サーバへの引き渡しまでです（最終的な受信箱への到達やバウンスの把握は外部要因になります）。

## 目的と解決する課題

Verbena は各クライアントの「メールを配送する」責務を分離するための独立したアプリケーションです。クライアントは EML を Verbena に渡すだけで、配送の実行・記録・再試行を Verbena 側に委譲できます。

次のような課題の解決を担います：

- クライアントごとに実装・運用している外部 SMTP との通信や失敗時の取り扱いをまとめたい
- 複数宛先の一部失敗を正確に把握し、失敗した宛先だけを再送したい

それらの課題に対処するため、Verbena は次の機能を提供します：

- 宛先単位での送信結果の記録
- 一時エラー時の自動再送
- 指定時刻の配送（予約配信）
- 失敗した宛先のみを対象にした再送

## 開発環境構築手順

開発環境は Docker Compose を利用します。

### 初回セットアップ

ローカル PC の任意のディレクトリに、 GitHub からリポジトリをクローンします。

```sh
$ git clone https://github.com/hiroaki/Verbena.git
```

そのディレクトリへ入り、開発ブランチ `develop` をチェックアウトします。

```sh
$ cd Verbena
$ git checkout develop
```

環境変数ファイルを作成します:

```sh
$ cp dot.env.sample .env
```

`.env` ファイルを編集して、データベースの認証情報を設定します。

#### データベース初期化用の環境変数

初回起動時、データベースコンテナは `./initdb` 配下のスクリプトを自動実行してデータベースユーザーの権限を設定します。この際、**以下の環境変数が必要です**（`.env` または compose.yml で指定）：

| 変数名               | 説明 |
|----------------------|------|
| `MYSQL_ROOT_PASSWORD`| MySQL rootユーザーのパスワード。初期化スクリプト用。必須。 |
| `MYSQL_USER`         | アプリ用DBユーザー名。必須。 |
| `MYSQL_PASSWORD`     | アプリ用DBユーザーパスワード。必須。 |

なお、ボリュームに既存のデータがある場合は初期化スクリプトが実行されません（完全に初期状態へ戻す場合は「データベースの完全リセット」を参照してください）。

イメージを作成し、そのコンテナを起動します。

```sh
$ docker compose build
$ docker compose up -d
```

サービス "web" からデータベースを作成します。

```sh
$ docker compose exec web rails db:migrate:reset
```

## 設定

### トークンの用意

メールデータ入力のための Web API へのアクセスには Bearer トークンによる認証が必要です。そのために、利用者ごとに Token レコードを作成してください：

```ruby
Token.create_unique!(label: "hoge", key: "user-secret", expires_at: 1.year.from_now)
```

- `key` の値は機密情報です。そのレコードの対象としている利用者以外に見られないよう保護してください。
- `label` は利用者の目印としてユニークな値を設定します。
- 有効期限は `expires_at` に設定し、その時刻まで有効です（必須）。
- 無効化は物理削除ではなく `revoked_at` をセットすることで行ってください（監査のため）。
- 作成時はモデルのファクトリ・メソッド `Token.create_unique!` を使用してください。

運用上の注意:

- トークンは管理者のみが発行・更新を行います。利用者は管理者から配布される `key` を使用するのみで、作成や更新はできません。
- 発行後の `key` の更新は設計で禁止しています。変更する必要が生じた場合は、既存トークンを `revoke!` して無効化し、新しいトークンを作成してください。
- 期限切れトークンを一括で無効化する Rake タスクを用意しています：

  ```sh
  # ドライラン（何件無効化されるかを確認）
  $ bundle exec rake verbena:tokens:revoke_expired[dry]

  # 実行（expires_at を過ぎ、まだ revoked されていないトークンを revoked にする）
  $ bundle exec rake verbena:tokens:revoke_expired
  ```

### 環境変数の設定

Verbena の設定は環境変数で行います。主な環境変数は次のとおりです。

| 変数名 | 説明 |
|--------|------|
| `VERBENA_DELIVERY_METHOD` | メール配送方式。smtp / test / file。既定値: test（開発）/smtp（本番）。 |
| `VERBENA_DELIVERY_SMTP_ADDRESS` | SMTP配送時のサーバアドレス。既定値: なし。 |
| `VERBENA_DELIVERY_SMTP_PORT` | SMTP配送時のポート番号。既定値: なし。 |
| `VERBENA_DELIVERY_SMTP_DOMAIN` | SMTP配送時のHELOドメイン。既定値: なし。 |
| `VERBENA_DELIVERY_SMTP_USER_NAME` | SMTP認証ユーザ名。既定値: なし。 |
| `VERBENA_DELIVERY_SMTP_PASSWORD` | SMTP認証パスワード。既定値: なし。 |
| `VERBENA_DELIVERY_SMTP_AUTHENTICATION` | SMTP認証方式。plain / login など。既定値: なし。 |

これらのほかにも、本番環境や Docker Compose を使わない環境など、initdb スクリプトを使わない場合は、アプリ側の DB 接続情報として `VERBENA_DATABASE_USER` / `VERBENA_DATABASE_PASSWORD` を設定してください。

詳細・全項目は [docs/ENVIRONMENT_VARIABLES.md](docs/ENVIRONMENT_VARIABLES.md) を参照してください。


## 実行方法

### メールデータ入力

送信対象のメールはテーブル `mail_queues` のレコードです（１レコード＝１通）。配送するメールの登録は、このレコードを作ることになります。

手元の環境から Rake タスク経由での登録、または外部のシステムから Web 経由で登録できます。いずれのインタフェースも、入力データ・フォーマットはメール・メッセージのソースである EML 形式である必要があります。

Rake タスクの場合は EML ファイルのパスを指定しながら、タスク "verbena:mail_queues:add" を実行します：

```sh
$ bin/rails verbena:mail_queues:add[/path/to/source.eml]
```

一方、外部のシステムから `mail_queues` へデータを入力するには Web API を経ます。エンドポイントに EML 形式のデータを POST することで、テーブル `mail_queues` のレコードが作成されます。このとき、リクエストヘッダ `Authorization` に、作成したトークンを含めて送る必要があります。

次の例は、メールのソース `/path/to/source.eml` を入力します：

```sh
$ curl -D - -H 'Authorization: Bearer user-secret' -X POST \
    -F 'mail_queue[eml]=@/path/to/source.eml' \
    http://localhost:23000/api/v1/mail_queues
```

いずれの場合でも、入力したメールのヘッダ "To:" "Cc:" "Bcc:" に記されたメールアドレスの数だけ（重複は除外して）`mail_queues` が作成されます。例えば `/path/to/source.eml` が次の内容であったとした場合、そのヘッダ "To:" "Cc:" "Bcc:" に基づき 4 件の `mail_queues` レコードが作成されます。

```sh
Date: Tue, 1 Jul 2003 10:52:37 +0200
From: me@example.com
To: you@example.com
Cc: ichiro@example.com, jirou@example.com
Bcc: saburo@example.com
Subject: =?UTF-8?Q?=E3=81=94=E6=8C=A8=E6=8B=B6?=
Content-Type: text/plain; charset="UTF-8"

こんにちは。
```

それらレコードの違いは、実際の送信先となるメールアドレスが格納されるカラム `envelope_to` のみです。メール配送はテーブル `mail_queues` のレコードごとに行われ、 EML データの内容に関わらず（ヘッダには複数の宛先が記載されていますが、それらは関係なく）、カラム `envelope_to` の宛先に送られます。

また、ヘッダ "Date:" は、作成される `mail_queue` レコードのタイマー時刻 `timer_at` カラムの値に使用されます。この入力の段階に於いては "Date:" は省略可能で、その際は `timer_at` の値には現在時刻が使用されます。

### メール配送

メール配送については Rake タスクを実行します。テーブル `mail_queues` にあるレコードのうち、次の条件のものが対象となります：

- session_id が NULL
- timer_at の日時が経過している

コマンド：

```sh
$ bin/rails verbena:delivery:by_timer
```

配送結果はテーブル `delivery_responses` に追記されます。

なお開発環境では、`VERBENA_DELIVERY_METHOD` の既定値は `test` のため、SMTP 送信は行われません（`Mail::TestMailer` に送られます）。

### 確保 / 再送

配送処理がスタックした場合や再送が必要な場合に利用する Rake タスクです。

配送処理では、各セッションがレコードを処理するために「確保」（session_id をセット）します。通常は処理が完了すれば配送されますが、何らかの理由で処理が途中で停止すると、レコードが確保されたまま放置され、他のプロセスが処理できない状態になります。

**スタック状態の解放（全セッション対象）:**

長時間確保されているが配送されていないレコードを、時間経過に基づいて自動的に「解放」（session_id を NULL に戻す）します。これは処理が異常停止した可能性のあるレコードを、セッションに関係なく強制的に解放するための操作です。

```sh
# 1時間より古い確保状態を解放（ドライラン）
$ bin/rails verbena:claim:release_stale[1,dry]

# 2時間より古い確保状態を実際に解放
$ bin/rails verbena:claim:release_stale[2]

# 現在の確保状態を表示
$ bin/rails verbena:claim:show_stale
```

**再送準備（特定セッション対象）:**

特定のセッションで配送を試みたが失敗した（4xxエラー）メッセージを再試行可能にします。または、特定のセッションで確保されたが配送結果が記録されていないメッセージ（上記のスタック状態と同じ状態）を再試行可能にします。これらは意図的に特定セッションのレコードを選択して再処理するための操作です。

```sh
# 直近の配送がステータス4xxであったメッセージを再送可能状態にする
# 注意: session_id は必須です
$ bin/rails verbena:delivery:prepare_retry[SESSION_ID]

# 配送結果が無いメッセージを再送可能状態にする
# 注意: session_id は必須です
$ bin/rails verbena:delivery:reset_undelivered[SESSION_ID]
```

**注意:** `prepare_retry` および `reset_undelivered` タスクは `session_id` が必須です。指定がない場合はエラーとなります。


## メンテナンス - 古いレコードの削除

各テーブルのレコードは送信処理後も残り続け、ディスク容量を圧迫して行く一方なので、定期的に削除するようにしてください。削除のための Rake タスクがあります。

例えば、配送処理か一週間を経過したメールを削除するには次のコマンドを実行します：

```sh
$ bin/rails verbena:cleanup:weekly

```

期限については `weekly` のほかにも `daily`, `monthly` や `now` もあります。

環境変数で保持期間を制御することもできます。`VERBENA_CLEANUP_TTL_DAYS`（既定 30）に日数を指定し、次のタスクを実行します。

```sh
$ VERBENA_CLEANUP_TTL_DAYS=45 bin/rails verbena:cleanup:by_ttl
```

実行前に削除件数だけを確認したい場合は dry-run が利用できます（削除は行われません）。

```sh
$ bin/rails verbena:cleanup:weekly[true]
$ bin/rails verbena:cleanup:by_ttl[true]
```

## 開発に関して

### テストの実行

テストは rspec を利用しています：

```sh
# 全テストを実行
docker compose exec web bundle exec rspec

# 特定ファイルだけ実行
docker compose exec web bundle exec rspec spec/tasks/verbena/mail_queues_rake_spec.rb
```

テストを実行すると `coverage` ディレクトリにカバレッジ・レポートが出力されますので、 `coverage/index.html` をブラウザで開いて、内容を確認してください。

### データベースの完全リセット

開発中にデータベースを完全に初期状態に戻したい場合は、以下の手順を実行します：

1. コンテナを停止してボリュームを削除:
  ```sh
  $ docker compose down -v
  ```

2. コンテナを再起動:
  ```sh
  $ docker compose up -d
  ```

3. データベースを再作成:
  ```sh
  $ docker compose exec web rails db:migrate:reset
  ```

### タイムゾーン方針 (UTC)

- Verbena（Rails）は常に UTC で動作するように設定します。
- データベースは OS タイムゾーンを UTC（`TZ=UTC`）に固定します。
- **MySQL/MariaDB**: `config/database.yml` の設定の中で `init_command: "SET time_zone = '+00:00'"` を指定し、セッションのタイムゾーンを UTC に固定します。
- **PostgreSQL**: `config/database.yml` の設定の中で `variables: { timezone: 'UTC' }` を指定し、セッションタイムゾーンを UTC に固定します。
- **SQLite**: セッション／データベースのタイムゾーン設定はありません。日時は Rails 側で UTC として生成・管理し、その値を保存してください。
- **共通ガイドライン**: プログラミングに於いて DB内の `NOW()` や `CURRENT_TIMESTAMP` などのタイムゾーンが影響する関数は使わず、 Rails で生成した日時値をバインドして利用してください。


### データベース互換性とストレージ方針

#### 対応データベース

Verbena は複数のデータベースシステムをサポートします：

| Database | Version | Status |
|----------|---------|--------|
| MySQL    | 8.0+    | ✅ Supported |
| MariaDB  | 10.6+   | ✅ Supported |
| PostgreSQL | 13+   | ✅ Planned (in progress) |
| SQLite   | 3.x     | ✅ Planned (in progress) |

#### EML データの保存方針

EML (Raw email format) は `eml_sources.eml` カラムに保存されます。

- **現在の方針（互換性優先）**:
  - データベースに保存する EML は plain `:text` 型を使用し、すべてのデータベースで互換性を確保しています。
  - MySQL の `TEXT` 型は約 64 KiB、PostgreSQL と SQLite の `text` は事実上無制限です。
  - 添付ファイルがない、または小さいメール（通常のビジネスメール）であれば、この制限内で対応可能です。

- **将来の拡張計画（オブジェクトストレージ対応予定）**:
  - より大きな EML ファイル（大きな添付ファイル付き）をサポートするために、オブジェクトストレージ（Amazon S3 等）の利用を検討しています。
  - その際は、EML 本体をストレージに保存し、DB には メタデータと小さなプレビューのみを保持します。

#### マイグレーションの互換性

すべてのマイグレーション（`db/migrate/`）は、以下の原則に従い、複数のデータベースで動作するように設計されています：

- **MySQL 専用オプション（`after:`、`charset:`、`collation:`）は使用しない**：MySQL 固有の `after:` などでカラム並び順を制御・前提とせず、実際の並び順は各データベース実装に依存するものとして、ポータブルな Rails マイグレーション構文を採用。
- **型固有のオプションはアダプタ非依存**：`:text` 型に対する MySQL 固有のサイズ指定オプション（`limit:` など）のように、DB ごとに挙動が異なる指定は使わず、すべての DB で解釈可能なプレーンな型指定のみを使用。
- **SQL の直接記述を避ける**：`execute()` 句で vendor-specific SQL を使わないよう注意。


## Contributing

Contributions are welcome! Please see `CONTRIBUTING.md` for guidelines.


## License

This project is licensed under the 0BSD license. See `LICENSE`.
