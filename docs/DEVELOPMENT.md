# Verbena Development Guide

This document provides information for Verbena developers, including environment setup, testing, architecture design, and the background of technical decisions.

## Table of Contents

- [Development Environment Setup](#development-environment-setup)
- [Deploy](#Deploy)
- [I18n / Locale](#i18n--locale)
- [Testing](#testing)
- [Architecture](#architecture)
- [Database Design](#database-design)
- [Token Operation Rules](#token-operation-rules)

---

## Development Environment Setup

### Prerequisites

- Docker and Docker Compose
- Git

### Initial Setup

1. **Clone the repository**

```sh
$ git clone https://github.com/hiroaki/Verbena.git
$ cd Verbena
$ git checkout develop
```

2. **Set environment variables**

*Before starting containers, you must set the "database initialization environment variables". See the later section ("Database Initialization Environment Variables") for details.*

Environment variables can be managed in `.env` files, `compose.yml`, and various `compose.*.yml` files.

The `.env` file is not required. Create or edit it only if you want to manage variables in an external file as needed.

```sh
$ cp dot.env.sample .env
```

If you specify environment variables directly in `compose.yml` or `compose.*.yml`, the `.env` file is unnecessary. Choose according to your operational needs.

3. **Select the database**

Verbena's Docker Compose setup uses a combination of "common (compose.yml) + DB overlay". Specify the files according to the database you want to use:

```sh
# MySQL / MariaDB
$ docker compose -f compose.yml -f compose.mysql.yml up -d

# PostgreSQL
$ docker compose -f compose.yml -f compose.postgresql.yml up -d

# SQLite (no DB service required)
$ docker compose -f compose.yml -f compose.sqlite.yml up -d
```

The following command examples use the MySQL overlay (`compose.mysql.yml`). If you use PostgreSQL or SQLite, replace the file names as appropriate.

4. **Build and start containers**

```sh
$ docker compose -f compose.yml -f compose.mysql.yml build
$ docker compose -f compose.yml -f compose.mysql.yml up -d
```

5. **Initialize the database**

```sh
$ docker compose -f compose.yml -f compose.mysql.yml exec web rails db:prepare
```

### Database Initialization Environment Variables

On first startup, the database container automatically runs scripts under `./initdb` to set database user privileges.

#### MySQL / MariaDB

The following environment variables are required (specify in `.env` or `compose.mysql.yml`):

| Variable Name         | Description |
|----------------------|-------------|
| `MYSQL_ROOT_PASSWORD`| MySQL root user password. Required for initialization scripts. Required. |
| `MYSQL_USER`         | DB username for the app. Required. |
| `MYSQL_PASSWORD`     | DB user password for the app. Required. |
| `DATABASE_NAME`      | Base name for the database. Default: `verbena` |

If you specify `DATABASE_NAME` in `.env`, the development DB will be automatically created as `${DATABASE_NAME}_development`.

#### PostgreSQL

The following environment variables are used (if not set, the table defaults are used):

| Variable Name | Description |
|---------------|-------------|
| `POSTGRES_USER` | PostgreSQL superuser name. Default: `postgres` |
| `POSTGRES_PASSWORD` | Password for the above superuser. Default: `postgres` |
| `VERBENA_DATABASE_USER` | DB username for the Rails app. Default: same as `POSTGRES_USER` |
| `VERBENA_DATABASE_PASSWORD` | Password for the above app user. Default: same as `POSTGRES_PASSWORD` |
| `DATABASE_NAME` | Base name for the database. Default: `verbena` |

If not specified, the application user and PostgreSQL superuser will use the same credentials, but you can set them separately for security requirements.

#### SQLite

SQLite is file-based, so no DB server environment variables are needed. Files are automatically created in the `storage/` directory.

#### Notes

- If there is existing data in the volume, the initialization script will not run.
- To return to a completely initial state, delete and recreate the volume.

---

## Deploy

TODO

---

## I18n / Locale

Verbena supports two languages: Japanese (ja) and English (en). The default is English.

- Default locale: `en`
- Fallback: `ja -> en`
- Configuration: `config/application.rb`
- Locale files: `config/locales/*.yml`
- Standard translations: Uses the `rails-i18n` gem

### Addition/Update Policy

- UI strings should use `t("...")`, and keys should be added to both `config/locales/en.yml` and `config/locales/ja.yml`.
- Model names/attribute names/error messages are organized under `activerecord.*`.
- API messages are fixed in English.

---

## Testing

### Running Tests

Tests use RSpec:

```sh
# Run all tests
$ docker compose -f compose.yml -f compose.mysql.yml exec web bundle exec rspec

# Run only a specific file
$ docker compose -f compose.yml -f compose.mysql.yml exec web bundle exec rspec spec/tasks/verbena/mail_queues_rake_spec.rb

# Run only a specific line
$ docker compose -f compose.yml -f compose.mysql.yml exec web bundle exec rspec spec/models/mail_queue_spec.rb:42
```

### Coverage Report

When you run tests, a coverage report is output to the `coverage` directory:

```sh
$ open coverage/index.html
```

---

## Architecture

### System Responsibility Scope

#### Delivery Scope

Verbena is responsible **up to handing off to the destination SMTP server**.

- **In scope**: Successful delivery from the application to the destination SMTP server (receiving SMTP response `250 OK`)
- **Out of scope**:
  - Delivery failure at relay servers (bounces)
  - Blocking by spam filters
  - Final inbox delivery
  - User opening/reading

This definition of responsibility is based on the technical characteristics of the SMTP protocol:

- The SMTP "250 OK" response only means that the server has accepted the email
- Failures in subsequent relays or final delivery cannot be detected immediately
- Subsequent bounces are usually returned to the sender as "bounce emails (DSN)"

According to the SMTP protocol specification, when the destination server returns `250 OK`, only "acceptance" is confirmed. There is no way for the sender to immediately know about subsequent relays, final inbox delivery, or bounces.

Also, bounces (delivery failure notifications) are sent back to the sender by the destination server later, asynchronously, and not always guaranteed. Therefore, real-time delivery confirmation and retry control are not implemented in standard SMTP mechanisms.

### Design Principles

#### 1. Safe Concurrency

- Uses **SolidQueue** to achieve scalable concurrency on a standard asynchronous job platform
- Stable delivery execution per job via `DeliveryJob`
- Robust error handling using job retry mechanisms

#### 2. Traceability

- All delivery attempts are recorded in `DeliveryResponse`
- Delivery process is visualized with structured logs
- Email tracking via `Message-ID`

#### 3. Flexible Delivery Control

- Timer-based delivery (delayed delivery): polling and enqueueing via `ScheduledDeliveryJob`
- Retry management for 4xx statuses: automatic recovery via retry processing on errors
- Adjustable batch size and concurrency

#### 4. Operational Ease

- Complete development and testing in Docker environment
- Daily operations via Rake tasks
- Environment variable management for configuration

### System Structure

#### Core Models

Verbena's core models clearly separate and manage each stage of the email delivery process.

- **EmlSource**: Stores received EML files (raw email data). One record per EML. Retains the original email content, including attachments and header information.

- **MailQueue**: Generates a delivery queue for each recipient. Multiple MailQueues may be created from one EML (e.g., broadcast to multiple recipients). Also manages scheduled delivery time, status, retry count, etc.

- **DeliveryResponse**: Records the result of each delivery attempt. One record is created for each delivery to an SMTP server, storing response content (e.g., 250 OK or error code), delivery time, retry info, etc.

The relationships between models are as follows:

```
EmlSource (raw EML storage)
  └─<1-to-many>─> MailQueue (delivery queue, per recipient)
      └─<1-to-many>─> DeliveryResponse (delivery result)
```

This structure allows flexible individual delivery to multiple recipients from a single email (EML), as well as retry and result tracking for each delivery.

#### Delivery Flow

Verbena's delivery flow consists of the following stages, from receiving the EML file to delivery completion and post-processing.

1. **Ingest**
  - EML files (raw email data) are uploaded or submitted by users or external systems.
  - `MailQueuesService` parses the EML and generates `MailQueue` records for each recipient.
  - This enables individual delivery to multiple recipients from a single email.

2. **Scheduling**
  - Each `MailQueue` is assigned a scheduled delivery time or immediate delivery flag.
  - For immediate delivery, `DeliveryJob` is enqueued immediately after `MailQueue` creation.
  - For scheduled delivery, `ScheduledDeliveryJob` runs periodically, detects queues whose scheduled time has arrived, and enqueues `DeliveryJob`.
  - This enables flexible scheduling such as delayed or batch delivery.

3. **Deliver**
  - `DeliveryJob` is started for each queue and performs delivery to the SMTP server via `DeliveryService`.
  - The success/failure and SMTP response are recorded in `DeliveryResponse`.
  - If an error occurs, retry control is performed, and if redelivery is needed, the job is enqueued again.

4. **Cleanup**
  - Cleanup (deletion) of completed `MailQueue` and unreferenced `EmlSource` is performed by running Rake tasks (e.g., `verbena:cleanup:weekly`) at any time by the user.
  - Periodic automatic execution is not set by default. Schedule with cron, etc., as needed.


This flow automates everything from EML reception to individual delivery to multiple recipients and recording delivery results, while leaving data retention/deletion operations to the user's discretion.

#### Email Data Input Mechanism

In Verbena, email data to be delivered (EML format) is stored in the `eml_sources` table. At the same time, for each recipient listed in the EML headers `To:`, `Cc:`, and `Bcc:`, a record is created in the `mail_queues` table as a delivery queue (duplicates are excluded).

##### Input Methods

- Via Rake task: Specify the EML file path and run `verbena:mail_queues:add`
- Via Web API: POST EML data (token required in `Authorization` header)

In either case, multiple `mail_queues` records are generated based on the EML recipient headers.

Example:

```sh
Date: Tue, 1 Jul 2003 10:52:37 +0200
From: me@example.com
To: you@example.com
Cc: ichiro@example.com, jirou@example.com
Bcc: saburo@example.com
Subject: ...
Content-Type: text/plain; charset="UTF-8"

Hello.
```

In this case, four `mail_queues` records are created.

The only difference between each record is the `envelope_to` column, which stores the actual recipient email address. Delivery processing is performed per record in `mail_queues`, and only the address in `envelope_to` is used, regardless of multiple recipients in the EML header.

Also, the value of the EML header `Date:` is stored in the `timer_at` column of the `mail_queues` table as the "scheduled delivery time". If `Date:` is omitted, the current time is set in `timer_at`.


### Future Expansion Plans

#### Bounce Management Feature (Next Milestone)

Managing bounces after delivery will improve actual deliverability.
See [BOUNCE_MANAGEMENT.md](BOUNCE_MANAGEMENT.md) for details.

#### Expected Expansion Features

- Delivery rate control (rate limiting)
- Limit on concurrent connections per recipient domain
- DKIM signature support
- Delivery statistics dashboard
- Webhook notifications

---

## Database Design

### Supported Databases

Verbena supports multiple database systems:

| Database   | Version | Status        |
|------------|---------|---------------|
| MySQL      | 8.0+    | ✅ Supported  |
| MariaDB    | 10.6+   | ✅ Supported  |
| PostgreSQL | 13+     | ✅ Supported  |
| SQLite     | 3.x     | ✅ Supported  |

### Migration Compatibility

All migrations (`db/migrate/`) are designed to work with multiple databases according to the following principles:

- **Do not use MySQL-specific options (`after:`, `charset:`, `collation:`)**: Do not control or assume column order with MySQL-specific options like `after:`; use portable Rails migration syntax, and treat actual order as DB-dependent.
- **Type-specific options are adapter-independent**: Do not use DB-specific options like MySQL's size specifier for `:text` (`limit:`), only use plain type specifiers that are interpreted by all DBs.
- **Avoid direct SQL**: Do not use vendor-specific SQL in `execute()` clauses.

### Schema Updates

When you add or change migrations, run bin/rails db:schema:dump in each DB environment and update the corresponding schema file.

| DATABASE_ADAPTER | Schema File              |
|------------------|--------------------------|
| mysql2           | db/schema.mysql2.rb      |
| postgresql       | db/schema.postgresql.rb  |
| sqlite3          | db/schema.sqlite3.rb     |

At container startup, the `entrypoint.sh` script places the schema file corresponding to the `DATABASE_ADAPTER` as `db/schema.rb`. Therefore, the `db/schema.rb` file is excluded from version control.

### Timezone Policy (UTC)

Verbena is designed to operate consistently in UTC:

- **Rails application**: Always operates in UTC (`config.time_zone = 'UTC'`)
- **Database OS**: Timezone fixed to UTC (`TZ=UTC`)
- **MySQL/MariaDB**: Specify `init_command: "SET time_zone = '+00:00'"` in `config/database.yml` to fix session timezone to UTC
- **PostgreSQL**: Specify `variables: { timezone: 'UTC' }` in `config/database.yml` to fix session timezone to UTC
- **SQLite**: No session/database timezone setting. Datetimes are generated/managed as UTC on the Rails side

### Programming Guidelines

- Do not use DB functions affected by timezone such as `NOW()` or `CURRENT_TIMESTAMP`; always bind datetime values generated by Rails
- Always treat datetimes as UTC, and convert to the user's timezone only when displaying

### EML Data Storage Policy

EML (Raw email format) is stored in the `eml_sources.eml` column.

#### Current Policy (Compatibility Priority)

- EML stored in the database uses plain `:text` type for compatibility with all databases
- MySQL's `TEXT` type is about 64 KiB; PostgreSQL and SQLite `text` is effectively unlimited
- For emails without attachments or with small attachments (typical business emails), this is sufficient

#### Future Expansion Plan (Object Storage Support Planned)

- To support larger EML files (with large attachments), we are considering using object storage
- In that case, the EML body will be stored in storage, and only metadata and a small preview will be kept in the DB

---

## Token Operation Rules

Bearer token authentication is required for Verbena's email data input (Rake/Web API). The following are notes on token management and operation.

- Only administrators can issue or update tokens. Users may only use the distributed `key` and cannot create or update tokens themselves.
- When issuing, use the model factory method `Token.create_unique!`.
- The value of `key` is confidential. Protect it so that it is not seen by anyone other than the intended user.
- Set a unique value for `label` as a marker for the user.
- Set the expiration date in `expires_at`; it is valid until that time (required).
- Invalidate by setting `revoked_at` instead of physical deletion (for audit purposes).
- Updating the `key` after issuance is prohibited (for security reasons, as the existence of another's key could be inferred from UNIQUE constraint violations). If a change is needed, revoke the existing token with `revoke!` and create a new one.
- To bulk-revoke expired tokens, use the Rake task `verbena:tokens:revoke_expired`.

Example:

```ruby
Token.create_unique!(label: "hoge", key: "user-secret", expires_at: 1.year.from_now)
```

Invalidate expired tokens:

```sh
# Dry run (check how many will be invalidated)
$ bundle exec rake verbena:tokens:revoke_expired[dry]

# Execute (set tokens to revoked if expires_at has passed and not yet revoked)
$ bundle exec rake verbena:tokens:revoke_expired
```
