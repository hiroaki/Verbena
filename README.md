# Verbena

Verbena is an EML-based mail queue and SMTP delivery service.

This project is currently under active development.

## 開発環境構築手順

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

`.env` ファイルを編集してデータベースの認証情報を設定します。開発環境では既定値をそのまま使用できますが、本番環境では必ず変更してください。

イメージを作成し、そのコンテナを起動します。

```sh
$ docker compose build
$ docker compose up -d
```

初回起動時、データベースコンテナは `./initdb` 配下のスクリプトを自動実行してデータベースユーザーの権限を設定します。このプロセスは冪等性があり、複数回実行しても安全です。

サービス "web" からデータベースを作成します。

```sh
$ docker compose exec web rails db:migrate:reset
```


### セキュリティに関する重要事項

- **開発環境**: 現状は Docker compose が読み取る `.env` ファイルでデータベース認証情報を管理しています。なおこのファイルはリポジトリにコミットしないでください（`.gitignore` で除外済み）。
- **本番環境**: Docker secrets や環境変数管理システムなど、安全な方法でデータベース認証情報を管理してください。


## 設定

### データベース初期化

MySQL 公式 Docker イメージの仕様により、コンテナ初回起動時に `/docker-entrypoint-initdb.d` ディレクトリ内のスクリプトが自動的に実行され、データベースの初期化が行われます。

- **初期化スクリプト**: `./initdb/00-create-db-users.sh` が配置されているディレクトリは、compose.yml の設定によりコンテナ内の `/docker-entrypoint-initdb.d` にマウントされます。
- **実行タイミング**: データベースコンテナの初回作成時（ボリュームにデータが存在しない場合のみ）
- **冪等性**: スクリプトは複数回実行しても安全です。既存の権限をチェックしてから設定を行います。
- **ログ**: 初期化プロセスはコンテナログで確認できます（`docker compose logs db`）

ただし、ボリュームに既存のデータがある場合、初期化スクリプトは実行されません。完全なリセットが必要な場合は後述する「データベースの完全リセット」手順を参照してください。

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

### SMTP/配送設定

アプリケーションの設定は環境変数で行います。

主要な環境変数：
- VERBENA_DELIVERY_METHOD=smtp|test|file（開発/テストは `test`、本番は `smtp` が想定の既定）
- VERBENA_DELIVERY_SMTP_ADDRESS, VERBENA_DELIVERY_SMTP_PORT, VERBENA_DELIVERY_SMTP_DOMAIN,
  VERBENA_DELIVERY_SMTP_USER_NAME, VERBENA_DELIVERY_SMTP_PASSWORD, VERBENA_DELIVERY_SMTP_AUTHENTICATION,
  VERBENA_DELIVERY_SMTP_ENABLE_STARTTLS_AUTO
- VERBENA_FILE_DELIVERY_DIR（file モード時の保存先。未指定時は `tmp/mails`）
- VERBENA_ENVELOPE_FROM_OVERRIDE（SMTP の envelope-from を強制上書き、任意）


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
    http://localhost:13000/api/v1/mail_queues
```

いずれの場合でも、入力したメールのヘッダ To: Cc: Bcc: に記されたメールアドレスの数だけ `mail_queues` が作成されます。例えば `/path/to/source.eml` が次の内容であったとした場合、そのヘッダ "To:" "Cc:" "Bcc:" に基づき 4 件の `mail_queues` レコードが作成されます。

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

なお開発環境では `VERBENA_DELIVERY_METHOD=test` の設定により、 SMTP 送信は行われません（`Mail::TestMailer` に送られます）。

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

## Contributing

Contributions are welcome! Please see `CONTRIBUTING.md` for guidelines.


## License

This project is licensed under the 0BSD license. See `LICENSE`.
