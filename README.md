# Verbena

Verbena is an EML-based mail queue and SMTP delivery service.


## 開発環境構築手順

### 初回セットアップ

ローカル PC の任意のディレクトリに、 GitHub からリポジトリをクローンします。

```
$ git clone https://github.com/hiroaki/Verbena.git
```

そのディレクトリへ入り、開発ブランチ `develop` をチェックアウトします。

```
$ cd Verbena
$ git checkout develop
```

環境変数ファイルを作成します（必須）:

```
$ cp dot.env.sample .env
```

`.env` ファイルを編集してデータベースの認証情報を設定します。開発環境では既定値をそのまま使用できますが、本番環境では必ず変更してください。

イメージを作成し、そのコンテナを起動します。

```
$ docker compose build
$ docker compose up -d
```

初回起動時、データベースコンテナは `./initdb` 配下のスクリプトを自動実行してデータベースユーザーの権限を設定します。このプロセスは冪等性があり、複数回実行しても安全です。

サービス "web" からデータベースを作成します。

```
$ docker compose exec web rails db:migrate:reset
```

### データベースの完全リセット

開発中にデータベースを完全に初期状態に戻したい場合は、以下の手順を実行します：

1. コンテナを停止してボリュームを削除:
   ```
   $ docker compose down -v
   ```

2. コンテナを再起動:
   ```
   $ docker compose up -d
   ```

3. データベースを再作成:
   ```
   $ docker compose exec web rails db:migrate:reset
   ```

**注意**: ボリュームを削除すると、データベース内のすべてのデータが失われます。本番環境では絶対に実行しないでください。

### セキュリティに関する重要事項

- **開発環境**: `.env` ファイルでデータベース認証情報を管理します。このファイルはリポジトリにコミットしないでください（`.gitignore` で除外済み）。
- **本番環境**: Docker secretsや環境変数管理システムなど、安全な方法でデータベース認証情報を管理してください。平文でのパスワード保存は避けてください。


## 設定

### データベース初期化について

MySQL 公式 Docker イメージの仕様により、コンテナ初回起動時に `/docker-entrypoint-initdb.d` ディレクトリ内のスクリプトが自動的に実行され、データベースの初期化が行われます。

- **初期化スクリプト**: `./initdb/00-create-db-users.sh`（ローカルパス）。compose.ymlの設定により、このディレクトリはコンテナ内の `/docker-entrypoint-initdb.d` にマウントされます。
- **実行タイミング**: データベースコンテナの初回作成時（ボリュームにデータが存在しない場合のみ）
- **冪等性**: スクリプトは複数回実行しても安全です。既存の権限をチェックしてから設定を行います。
- **ログ**: 初期化プロセスはコンテナログで確認できます（`docker compose logs db`）

**重要**: ボリュームに既存のデータがある場合、初期化スクリプトは実行されません。完全なリセットが必要な場合は上記の「データベースの完全リセット」手順を参照してください。

### トークンの用意

メールデータ入力のための Web API へのアクセスには Bearer トークンによる認証が必要です。

概要:

- アプリケーションの API には `Bearer <token>` ヘッダでの認証が必要です。
- トークンはサーバ側で平文 `key` をハッシュ化して保存します（`key_digest_hash`）。

作成例（Rails コンソール）:

```
Token.create!(label: "hoge", key: "secret", expires_at: 1.year.from_now)
```

ポイント:

- `key` は秘密です。ログや UI に平文を残さないでください。
- Bearer ヘッダの形式は token68 準拠を想定しています（例: `Authorization: Bearer <token>`）。
- `label` は配布先の目印として任意に付与できます。リポジトリの設計では `label` はユニークです。
- トークンの有効期限は `expires_at` で管理します（指定があればその時刻まで有効）。
- トークンの無効化は物理削除ではなく `revoked_at` をセットすることで行ってください（監査のため）。

運用上の注意:

- 発行後の `key` の直接更新はモデルで禁止しています（`prevent_key_change`）。キーを変更する場合は既存トークンを `revoke!` して無効化し、新しいトークンを作成する運用にしてください。
- 管理者専用の機能としてトークンを発行・取り扱う想定です。エンドユーザーにトークン作成・変更権限を与えないでください。
- 同じ `key` が複数存在すると識別情報が漏れるため、サーバ側でハッシュの一意性チェックを行っています（DB にも UNIQUE インデックスあり）。

定期無効化タスク:

- 期限切れトークンを一括で無効化する Rake タスクを用意しています。管理者が手動で実行できます。

```
# ドライラン（何件無効化されるかを確認）
bundle exec rake verbena:tokens:revoke_expired[dry]

# 実行（expires_at を過ぎた未revoked なトークンの revoked_at をセット）
bundle exec rake verbena:tokens:revoke_expired
```

利用例（curl）:

```
curl -H 'Authorization: Bearer secret' -X POST \
   -F 'mail_queue[eml]=@/path/to/source.eml' \
   http://localhost:13000/api/v1/mail_queues
```

このセクションは運用ポリシーに関わるため、必要に応じて管理者向けドキュメントに手順（無効化→再作成フローやログ記録方法）を追記してください。


### SMTP/配送設定（ENV-first）

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

```
$ bin/rails verbena:mail_queues:add[/path/to/source.eml]

```

一方、外部のシステムから `mail_queues` へデータを入力するには Web API を経ます。エンドポイントに EML 形式のデータを POST することで、テーブル `mail_queues` のレコードが作成されます。このとき、リクエストヘッダ Authorization に、作成したトークンを含めて送る必要があります。

次の例は、メールのソース `/path/to/source.eml` を入力します：

```
$ curl -D - -H 'Authorization: Bearer secret' -X POST \
    -F 'mail_queue[eml]=@/path/to/source.eml' \
    http://localhost:13000/api/v1/mail_queues
```

いずれの場合でも、入力したメールのヘッダ To: Cc: Bcc: に記されたメールアドレスの数だけ `mail_queues` が作成されます。例えば `/path/to/source.eml` が次の内容であったとした場合、そのヘッダ To: Cc: Bcc: に基づき 4 件の `mail_queues` レコードが作成されます。

```
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

```
$ bin/rails verbena:delivery:by_timer
```

開発環境では `VERBENA_DELIVERY_METHOD=test` の設定により、 SMTP 送信は行われません（`Mail::TestMailer` に送られます）。

また配送結果はテーブル `delivery_responses` に追記されます。

## メンテナンス - 古いレコードの削除

各テーブルのレコードは送信処理後も残り続け、ディスク容量を圧迫して行く一方なので、定期的に削除するようにしてください。削除のための Rake タスクがあります。

例えば、配送処理か一週間を経過したメールを削除するには次のコマンドを実行します：

```
$ bin/rails verbena:cleanup:weekly

```

期限については `weekly` のほかにも `daily`, `monthly` や `now` もあります。

環境変数で保持期間を制御することもできます。`VERBENA_CLEANUP_TTL_DAYS`（既定 30）に日数を指定し、次のタスクを実行します。

```
$ VERBENA_CLEANUP_TTL_DAYS=45 bin/rails verbena:cleanup:by_ttl
```

実行前に削除件数だけを確認したい場合は dry-run が利用できます（削除は行われません）。

```
$ bin/rails verbena:cleanup:weekly[true]
$ bin/rails verbena:cleanup:by_ttl[true]
```

## Contributing

Contributions are welcome! Please see `CONTRIBUTING.md` for guidelines.


## License

This project is licensed under the 0BSD license. See `LICENSE`.
