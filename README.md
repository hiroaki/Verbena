# Verbena

Verbena is an EML-based mail queue and SMTP delivery service.


## 開発環境構築手順

ローカル PC の任意のディレクトリに、 GitHub からリポジトリをクローンします。

```
$ git clone https://github.com/hiroaki/Verbena.git
```

そのディレクトリへ入り、開発ブランチ `develop` をチェックアウトします。

```
$ cd Verbena
$ git checkout develop
```

イメージを作成し、そのコンテナを起動します。

```
$ docker compose build
$ docker compose up -d
```

サービス "web" からデータベースを作成します。

```
$ docker compose exec web rails db:migrate:reset
```


## 設定

### トークンの用意

メールデータ入力のための Web API へのアクセスには Bearer トークンによる認証が必要です。

例として、トークンを "secret" で作成するには、 Rails コンソールから次のようにします：

```
Token.create!(label: "hoge", key: "secret")
```

`key` の値が認証のための秘密の文字列になります。その値となる Bearer トークンの書式は token68 というフォーマットに従う必要があります。

`label` は任意の文字列ですがユニークにします（トークン配布先の目印にするなど）。


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
