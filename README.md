# Verbena

Verbena is an **email delivery gateway** that receives EML-format emails from multiple client applications, manages delivery to external SMTP servers, and centrally records the results.

## Purpose

Verbena is an independent application designed to separate the responsibility of "sending emails" from each client. Clients simply pass EML files to Verbena, and Verbena handles delivery, logging, and retries.

Note: Verbena is responsible only up to handing off to the SMTP server. Final inbox delivery and bounce management are out of scope.

**Problems Solved:**

- Centralizes communication with external SMTP servers and error handling, which would otherwise be implemented and operated by each client.
- Enables accurate identification and resending of failed recipients when sending to multiple addresses.

**Features Provided:**

- **Separation of delivery responsibility**: Clients only need to provide EML files. Delivery, retry, and logging are handled by Verbena.
- **Per-recipient management**: Each recipient in a multi-address send is logged individually, and only failed recipients can be resent.
- **Automatic retry**: Temporary errors are automatically retried by background jobs.
- **Scheduled delivery**: Delivery can be delayed until a specified time.

## Setup

### 1. Token Creation

Bearer token authentication is required for EML registration (via Rake/Web API). Administrators issue tokens for each user:

```ruby
Token.create_unique!(label: "client-name", key: "secret-key", expires_at: 1.year.from_now)
```

**Operational Notes:**
- Only administrators can issue or update tokens. Users may only use the distributed `key` and cannot create or update tokens themselves.
- Updating a `key` after issuance is prohibited. If a change is needed, revoke the existing token with `revoke!` and create a new one.
- To bulk-revoke expired tokens, use the Rake task `verbena:tokens:revoke_expired`.

### 2. Environment Variable Configuration

Key configuration items:

| Variable Name | Description | Default |
|---------------|-------------|---------|
| `VERBENA_DELIVERY_METHOD` | Delivery method (smtp/test/file) | test (development) / smtp (production) |
| `VERBENA_DELIVERY_SMTP_ADDRESS` | SMTP server address | - |
| `VERBENA_DELIVERY_SMTP_PORT` | SMTP port | - |
| `VERBENA_DELIVERY_SMTP_USER_NAME` | SMTP authentication user | - |
| `VERBENA_DELIVERY_SMTP_PASSWORD` | SMTP authentication password | - |

See [docs/ENVIRONMENT_VARIABLES.md](docs/ENVIRONMENT_VARIABLES.md) for all items.


## Usage

### Starting the Server

To start Verbena, run the following command:

```sh
$ bin/dev
```

This command starts both the Rails server and the background job process for delivery handling.

### Email Input

EML-format emails are saved as-is to the `eml_sources` table, and delivery queues (records in the `mail_queues` table) are created for each recipient.

There are two ways to register emails:

**Via Rake Task**

```sh
# Specify the token via environment variable
$ VERBENA_TOKEN=your-secret-key bin/rails verbena:mail_queues:add[/path/to/source.eml]

# Or specify the token as an argument
$ bin/rails verbena:mail_queues:add[/path/to/source.eml,token:your-secret-key]
```

**Via Web API**

```sh
$ curl -H 'Authorization: Bearer your-token' -X POST \
    -F 'mail_queue[eml]=@/path/to/source.eml' \
    http://localhost:23000/api/v1/mail_queues
```

For each recipient listed in the EML headers `To:`, `Cc:`, and `Bcc:`, a `mail_queues` record is created (duplicates are excluded).

The value of the `Date:` header is stored in the `timer_at` column of the same table as the "scheduled delivery time".

### Email Delivery

Delivery is automatically performed by SolidQueue background jobs. Records whose `timer_at` has passed are processed in order, and results are recorded in the `delivery_responses` table.

In development, no actual sending occurs because `VERBENA_DELIVERY_METHOD=test`.

## Job Management UI

Mission Control Jobs is used for job management. Basic authentication (set via environment variables `VERBENA_ADMIN_USERNAME` / `VERBENA_ADMIN_PASSWORD`) is required.

http://localhost:23000/admin/jobs


## Maintenance

### Deleting Old Records

Delivered records accumulate over time, so please delete them periodically:

```sh
# Delete records older than one week
$ bin/rails verbena:cleanup:weekly

# Delete by TTL (default 30 days)
$ VERBENA_CLEANUP_TTL_DAYS=45 bin/rails verbena:cleanup:by_ttl

# Dry run (check only the number of records to be deleted)
$ bin/rails verbena:cleanup:weekly[true]
```

### Manual Retry (Troubleshooting)

Normally, failed deliveries are automatically retried by background jobs. If the automatic retry limit is exceeded or an administrator wants to retry, use the following manual commands.

#### 1. Retry Temporary 4xx Errors

Only messages whose most recent delivery result was a 4xx (temporary error) are added to the retry queue. 5xx (permanent errors) are excluded.

```sh
$ bin/rails verbena:delivery:prepare_retry
```

> **Note:** 5xx errors are permanent. Please check the cause before recovery and register a new message if necessary.

#### 2. Reset Undelivered Messages

Resets messages that have no delivery result (not delivered for over 24 hours), regardless of error type.

```sh
$ bin/rails verbena:delivery:reset_undelivered
```

## Development

### Quick Start

```sh
# Clone the repository
$ git clone https://github.com/hiroaki/Verbena.git
$ cd Verbena

# Create environment variable file
$ cp dot.env.sample .env

# Select database and start containers (example: MySQL)
$ docker compose -f compose.yml -f compose.mysql.yml build
$ docker compose -f compose.yml -f compose.mysql.yml up -d

# Initialize the database
$ docker compose -f compose.yml -f compose.mysql.yml exec web bin/rails db:migrate:reset

# Run tests
$ docker compose -f compose.yml -f compose.mysql.yml exec web bundle exec rspec

# Start the server (see Procfile.dev)
$ docker compose -f compose.yml -f compose.mysql.yml exec web bin/dev
```

**Supported Databases**: MySQL 8.0+, MariaDB 10.6+, PostgreSQL 13+, SQLite 3.x

### Further Documentation

For details on development environment, architecture, and technical decisions, see:

- **[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)** - Development environment setup, testing, architecture, database design
- **[CONTRIBUTING.md](CONTRIBUTING.md)** - Contribution guidelines

## License

This project is licensed under the 0BSD license. See [LICENSE](LICENSE).
