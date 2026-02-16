# Verbena Environment Variable Reference

This document describes the environment variables used to configure the Verbena application.

For developer-oriented details, such as behavior, types, and value normalization, see `config/initializers/verbena_env.rb`.

## Database Settings

Database connection information is referenced by Rails in [config/database.yml](../config/database.yml).

| Variable Name | Purpose | Required/Optional | Default | Description |
|--------------|---------|------------------|---------|-------------|
| DATABASE_ADAPTER | Adapter selection | Optional (auto-set by Compose) | None | One of mysql2 / postgresql / sqlite3. Required if running Rails directly locally |
| DATABASE_NAME | DB base name | Optional | verbena | Determines the DB name for each environment as `#{DATABASE_NAME}_<environment>` |
| DATABASE_HOST | DB host | Optional | 127.0.0.1 | DB hostname/address. Compose automatically sets the container name |
| DATABASE_PORT | DB port | Optional | Adapter default (mysql2: 3306, postgresql: 5432) | DB port number |
| DATABASE_FILE | SQLite file | Optional | storage/verbena_<environment>.sqlite3 | DB file path when using SQLite |

| Variable Name | Purpose | Required/Optional | Default | Description |
|--------------|---------|------------------|---------|-------------|
| VERBENA_DATABASE_USER | DB user | Required in production | None | DB connection username |
| VERBENA_DATABASE_PASSWORD | DB password | Required in production | None | DB connection password |

In development (Docker Compose), you can omit `VERBENA_DATABASE_*` because each DB overlay sets adapter-specific credentials (e.g., `MYSQL_USER` / `MYSQL_PASSWORD` for MySQL, `POSTGRES_USER` / `POSTGRES_PASSWORD` for PostgreSQL), so it works as is.

**Note**: In production or environments not using Docker Compose (where initdb scripts are not used), set `VERBENA_DATABASE_USER` / `VERBENA_DATABASE_PASSWORD` for the app's DB connection.

## Delivery Settings

### Basic Settings

| Variable Name | Purpose | Required/Optional | Default | Description |
|--------------|---------|------------------|---------|-------------|
| VERBENA_DELIVERY_METHOD | Delivery method | Optional | test (development) / smtp (production) | smtp / test / file |
| VERBENA_ENVELOPE_FROM_OVERRIDE | Envelope-From override | Optional | None | Force override of SMTP envelope-from |
| VERBENA_DELIVERY_MAX_RETRIES | Delivery retry count | Optional | 5 | Maximum number of retries for network errors or temporary SMTP 4xx errors (passed to ActiveJob's `retry_on`) |
| VERBENA_DELIVERY_LOCK_TTL_SECONDS | Base lock period for delivery (seconds) | Optional | 300 | Base lock time (seconds) set as `MailQueue.locked_until` for delivery processing. Multiplied by attempt count (attempt 1 => base * 1). |
| VERBENA_DELIVERY_LOCK_MAX_SECONDS | Max lock period for delivery (seconds) | Optional | 3600 | Upper limit (seconds) for the value of `VERBENA_DELIVERY_LOCK_TTL_SECONDS` multiplied by attempt count. Prevents excessive lock extension for long sends. |

### SMTP Settings

These settings are required when using SMTP delivery (`VERBENA_DELIVERY_METHOD=smtp`).

| Variable Name | Purpose | Required/Optional | Default | Description |
|--------------|---------|------------------|---------|-------------|
| VERBENA_DELIVERY_SMTP_ADDRESS | SMTP server | Required for smtp | None | Server address for SMTP delivery |
| VERBENA_DELIVERY_SMTP_PORT | SMTP port | Required for smtp | None | Port number for SMTP delivery |
| VERBENA_DELIVERY_SMTP_DOMAIN | SMTP domain | Required for smtp | None | HELO domain for SMTP delivery |
| VERBENA_DELIVERY_SMTP_USER_NAME | SMTP username | Required for smtp | None | SMTP authentication username |
| VERBENA_DELIVERY_SMTP_PASSWORD | SMTP password | Required for smtp | None | SMTP authentication password |
| VERBENA_DELIVERY_SMTP_AUTHENTICATION | SMTP authentication method | Required for smtp | None | plain / login, etc. |
| VERBENA_DELIVERY_SMTP_ENABLE_STARTTLS_AUTO | Enable STARTTLS | Optional | true | Enable STARTTLS for SMTP |

### File Delivery Settings

Settings for file delivery (`VERBENA_DELIVERY_METHOD=file`).

| Variable Name | Purpose | Required/Optional | Default | Description |
|--------------|---------|------------------|---------|-------------|
| VERBENA_FILE_DELIVERY_DIR | File delivery destination | Optional for file | tmp/mails | Save destination in file mode |

## API Settings

### Pagination

Settings for pagination parameters when retrieving MailQueues index via API.

| Variable Name | Purpose | Required/Optional | Default | Description |
|--------------|---------|------------------|---------|-------------|
| VERBENA_API_PAGINATION_DEFAULT_LIMIT | API pagination default count | Optional | 50 | Default number of items in API response |
| VERBENA_API_PAGINATION_LIMIT_CAP | API pagination upper limit | Optional | 1000 | Maximum number of items in API response |
| VERBENA_API_PAGINATION_DEFAULT_OFFSET | API pagination default offset | Optional | 0 | Default offset in API response |

### Response Embedding (responses) Limit

Settings for the number of delivery responses (DeliveryResponses) included when retrieving MailQueue records via API (when `include=responses` parameter is specified).

| Variable Name | Purpose | Required/Optional | Default | Description |
|--------------|---------|------------------|---------|-------------|
| VERBENA_API_RESPONSES_DEFAULT_LIMIT | Default count | Optional | 50 | Default number of `responses` to include. Used if value is 0 or not specified |
| VERBENA_API_RESPONSES_LIMIT_CAP | Upper limit | Optional | 100 | Maximum allowed if `responses_limit` parameter is specified. If more retries are needed, review retry settings |

## Data Maintenance

### Size Limit

| Variable Name | Purpose | Required/Optional | Default | Description |
|--------------|---------|------------------|---------|-------------|
| VERBENA_EML_MAX_BYTES | Max EML size | Optional | 10485760 | Maximum bytes for received EML |

### Cleanup

| Variable Name | Purpose | Required/Optional | Default | Description |
|--------------|---------|------------------|---------|-------------|
| VERBENA_CLEANUP_TTL_DAYS | Cleanup retention days | Optional | 30 | Retention days for delivered data |

## System Settings

| Variable Name | Purpose | Required/Optional | Default | Description |
|--------------|---------|------------------|---------|-------------|
| VERBENA_LOG_FORMAT | Log output format | Optional | text | text / json |
| VERBENA_ADMIN_USERNAME | Admin username | Optional | None | Username for Basic authentication. If unset, cannot access admin UI |
| VERBENA_ADMIN_PASSWORD | Admin password | Optional | None | Password for Basic authentication. If unset, cannot access admin UI |
| VERBENA_TOKEN | Token for tasks | Required for task execution | None | API token key used in `verbena:mail_queues:*` Rake tasks |
