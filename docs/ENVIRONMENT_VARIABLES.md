# Verbena 環境変数リファレンス

Verbena アプリケーションの設定に用いられる環境変数を説明します。

開発者向けの情報として、詳細な挙動や型、値の正規化については `config/initializers/verbena_env.rb` を参照してください。

## データベース設定

データベース接続情報は Rails の [config/database.yml](../config/database.yml) で参照されます。

| 変数名 | 用途 | 必須/任意 | 既定値 | 説明 |
|--------|------|-----------|--------|------|
| VERBENA_DATABASE_USER | DBユーザー | 本番必須 | なし | DB接続ユーザー名 |
| VERBENA_DATABASE_PASSWORD | DBパスワード | 本番必須 | なし | DB接続パスワード |

開発環境（Docker Compose）では `VERBENA_DATABASE_*` が未設定の場合、`config/database.yml` の設定により `MYSQL_USER` / `MYSQL_PASSWORD` にフォールバックします。

**注意**: 本番環境や Docker Compose を使わない環境などで initdb スクリプトを使わない場合は、アプリ側の DB 接続情報として `VERBENA_DATABASE_USER` / `VERBENA_DATABASE_PASSWORD` を設定してください。

## 配送設定

### 基本設定

| 変数名 | 用途 | 必須/任意 | 既定値 | 説明 |
|--------|------|-----------|--------|------|
| VERBENA_DELIVERY_METHOD | 配送方式 | 任意 | test（開発）/smtp（本番） | smtp / test / file |
| VERBENA_ENVELOPE_FROM_OVERRIDE | Envelope-From上書き | 任意 | なし | SMTPのenvelope-from強制上書き |

### SMTP設定

SMTP配送（`VERBENA_DELIVERY_METHOD=smtp`）を使用する場合に必要な設定です。

| 変数名 | 用途 | 必須/任意 | 既定値 | 説明 |
|--------|------|-----------|--------|------|
| VERBENA_DELIVERY_SMTP_ADDRESS | SMTPサーバ | smtp時必須 | なし | SMTP配送時のサーバアドレス |
| VERBENA_DELIVERY_SMTP_PORT | SMTPポート | smtp時必須 | なし | SMTP配送時のポート番号 |
| VERBENA_DELIVERY_SMTP_DOMAIN | SMTPドメイン | smtp時必須 | なし | SMTP配送時のHELOドメイン |
| VERBENA_DELIVERY_SMTP_USER_NAME | SMTPユーザ名 | smtp時必須 | なし | SMTP認証ユーザ名 |
| VERBENA_DELIVERY_SMTP_PASSWORD | SMTPパスワード | smtp時必須 | なし | SMTP認証パスワード |
| VERBENA_DELIVERY_SMTP_AUTHENTICATION | SMTP認証方式 | smtp時必須 | なし | plain / login など |
| VERBENA_DELIVERY_SMTP_ENABLE_STARTTLS_AUTO | STARTTLS有効 | 任意 | true | SMTPでSTARTTLSを有効化 |

### ファイル配送設定

ファイル配送（`VERBENA_DELIVERY_METHOD=file`）を使用する場合の設定です。

| 変数名 | 用途 | 必須/任意 | 既定値 | 説明 |
|--------|------|-----------|--------|------|
| VERBENA_FILE_DELIVERY_DIR | ファイル配送先 | file時任意 | tmp/mails | fileモード時の保存先 |

## 処理制御

### 並列・バッチ処理

| 変数名 | 用途 | 必須/任意 | 既定値 | 説明 |
|--------|------|-----------|--------|------|
| VERBENA_PARALLEL_TYPE | 並列処理方式 | 任意 | in_threads | in_threads など |
| VERBENA_PARALLEL_CONCURRENCY | 並列数 | 任意 | 2 | 並列配送時のスレッド数等 |
| VERBENA_IN_BATCHES_OF | バッチサイズ | 任意 | 100 | 一括配送時のバッチ件数 |

### リトライ・バックオフ

| 変数名 | 用途 | 必須/任意 | 既定値 | 説明 |
|--------|------|-----------|--------|------|
| VERBENA_CLAIM_BACKOFF_BASE_SECONDS | クレーム初期待機秒 | 任意 | 1.0 | 配送リトライ時の初期待機秒数 |
| VERBENA_CLAIM_BACKOFF_CAP_SECONDS | クレーム最大待機秒 | 任意 | 300.0 | 配送リトライ時の最大待機秒数 |
| VERBENA_CLAIM_MAX_RETRIES | クレーム最大リトライ回数 | 任意 | 5 | 配送リトライの最大回数 |

## API設定

### ページネーション

API で MailQueues のインデックスを取得する際のページネーション・パラメータの設定です。

| 変数名 | 用途 | 必須/任意 | 既定値 | 説明 |
|--------|------|-----------|--------|------|
| VERBENA_API_PAGINATION_DEFAULT_LIMIT | APIページネーション既定件数 | 任意 | 50 | APIレスポンスのデフォルト件数 |
| VERBENA_API_PAGINATION_LIMIT_CAP | APIページネーション上限 | 任意 | 1000 | APIレスポンスの最大件数 |
| VERBENA_API_PAGINATION_DEFAULT_OFFSET | APIページネーション既定オフセット | 任意 | 0 | APIレスポンスのデフォルトオフセット |

### レスポンス埋め込み（responses）上限

API で MailQueue のレコードを取得する際に、その配送レスポンスの情報（DeliveryResponses）を含める場合（パラメータに `include=responses` を指定した場合）の、その件数についての設定です。

| 変数名 | 用途 | 必須/任意 | 既定値 | 説明 |
|--------|------|-----------|--------|------|
| VERBENA_API_RESPONSES_DEFAULT_LIMIT | 既定件数 | 任意 | 50 | 含める `responses` の既定取得件数。0 以下の値や未指定時はこの値が使われます |
| VERBENA_API_RESPONSES_LIMIT_CAP | 取得上限 | 任意 | 100 | `responses_limit` パラメータが指定された場合の最大許容件数。これを超えるような再送信の試行が認められる場合は、リトライの設定を見直してください |

## データ保守

### サイズ制限

| 変数名 | 用途 | 必須/任意 | 既定値 | 説明 |
|--------|------|-----------|--------|------|
| VERBENA_EML_MAX_BYTES | EML最大サイズ | 任意 | 10485760 | 受信EMLの最大バイト数 |

### クリーンアップ

| 変数名 | 用途 | 必須/任意 | 既定値 | 説明 |
|--------|------|-----------|--------|------|
| VERBENA_CLEANUP_TTL_DAYS | クリーンアップ保持日数 | 任意 | 30 | 配送済みデータの保持日数 |

## システム設定

| 変数名 | 用途 | 必須/任意 | 既定値 | 説明 |
|--------|------|-----------|--------|------|
| VERBENA_LOG_FORMAT | ログ出力形式 | 任意 | text | text / json |
