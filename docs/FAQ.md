(Created by Claude Sonnet 4.5, revised by GPT-5.2-Codex)
---

# Verbena FAQ

## Delivery Guarantees

### Q. Can I know if the email actually reached the user's inbox?

**A. No, Verbena only guarantees delivery up to the destination SMTP server.**

Due to the SMTP protocol specification, there are the following limitations:

1. When the SMTP server returns "250 OK", it means the server has accepted the email
2. Subsequent relaying and final inbox delivery are the responsibility of the receiving server
3. Bounces or inbox delivery at relay servers cannot be directly detected by Verbena

This is a limitation common to almost all email delivery systems (including commercial SaaS), not just Verbena.

### Q. So, does that mean I can't know if the user actually received the email?

**A. By managing bounces (delivery failure notifications), you can improve practical deliverability.**

If delivery fails at a relay, a "bounce email" (DSN: Delivery Status Notification) is usually returned to the Return-Path address.

Verbena plans to implement a **bounce management feature** as a future milestone:

1. Automatically collect and parse bounce emails (using [Sisimai](https://sisimai.org/))
2. Register undeliverable addresses to a blacklist
3. Automatically exclude them from future deliveries

See [BOUNCE_MANAGEMENT.md](BOUNCE_MANAGEMENT.md) for details.

### Q. Can I track whether an email was opened?

**A. Verbena does not have an open tracking feature.**

Tracking email opens requires other mechanisms, such as:

- Embedding a tracking pixel (transparent 1x1 image) in HTML emails
- Measuring link clicks (converting URLs to go through a tracking server)

However, these methods have limitations:

- If the mail client is set not to display images automatically, opens cannot be detected
- Privacy protection features (such as iOS Mail Privacy Protection) can disable tracking
- Legal regulations (such as GDPR) must be considered

Verbena's responsibility is "SMTP delivery management"; open tracking is out of scope.

## Bounce Management

### Q. Can bounces be detected in real time?

**A. Immediate SMTP-level errors (4xx/5xx) can be detected, but bounces at relay servers are delayed.**

**Detected immediately:**
- Immediate rejection from the destination SMTP server (e.g., 554 Relay access denied)
- Exceptions due to invalid address format (Net::SMTPSyntaxError)

**Detected with delay:**
- Bounces at relay servers (minutes to hours later)
- Drops by spam filters (sometimes no bounce is returned)

The bounce management feature is expected to periodically (e.g., hourly) collect and parse bounce emails.

### Q. How are temporary errors (4xx) and permanent errors (5xx) handled?

**A. The basic policy is: temporary errors are retried, permanent errors are blacklisted (planned for the future).**

**Examples of 4xx (temporary errors):**
- 450 Mailbox full
- 451 Temporary local problem
- 452 Insufficient storage

→ Will be retried for a certain period/number of times in the future

**Examples of 5xx (permanent errors):**
- 550 User unknown
- 551 User not local
- 554 Message rejected

→ Will be blacklisted in the future, and further deliveries will be stopped

## System Design

### Q. Why did you choose SolidQueue?

**A. Because it is a Rails standard feature, offering high reliability and maintainability.**

Previously, we implemented our own DB polling and locking mechanism (Claim feature), but with Rails 8, we migrated to the standard SolidQueue.
This reduced the maintenance cost of complex lock management and deadlock prevention, and enabled us to use standard asynchronous processing patterns.

### Q. Can Verbena integrate with other delivery systems?

**A. For bounce list reference, we plan to provide an API in the future.**

In the bounce management feature (Phase 3), we plan to make the blacklist accessible via REST API.
This will allow other systems to use only the blacklist management, even without using Verbena's delivery features.

See [BOUNCE_MANAGEMENT.md](BOUNCE_MANAGEMENT.md) for details.

## Operations

### Q. How is performance for large-scale delivery?

**A. It scales by adjusting the number of SolidQueue workers and concurrency.**

You can adjust with the following settings:

```yaml
# config/queue.yml
workers:
  - queues: "*"
    threads: 3
    processes: <%= ENV.fetch("JOB_CONCURRENCY", 1) %>
```

Actual throughput depends on the performance of the SMTP server and network environment.

### Q. What happens to jobs that stop processing?

**A. SolidQueue manages them, and failed jobs are recorded in the `solid_queue_failed_executions` table.**

You can check and retry with the following methods:

```ruby
# Check failed jobs
SolidQueue::FailedExecution.count
SolidQueue::FailedExecution.last.error

# Retry failed jobs
SolidQueue::FailedExecution.last.retry
```

### Q. How should I manage logs?

**A. Structured JSON log output is supported.**

Set the environment variable `VERBENA_LOG_FORMAT=json` to output in JSON Lines format.
This makes it easy to aggregate and analyze with Fluentd, Logstash, CloudWatch Logs, etc.

```json
{"event":"deliver.result","level":"info","mail_queue_id":42,"message_id":"<xyz@example.com>","smtp_status":"250","message":"OK sending..."}
```

## Troubleshooting

### Q. Delivery seems to be stuck

**Checklist:**

1. **Check for queued jobs**
   ```ruby
   SolidQueue::Job.count
   SolidQueue::ScheduledExecution.count  # Waiting for scheduled execution
   SolidQueue::ReadyExecution.count      # Waiting for execution
   SolidQueue::ClaimedExecution.count    # In progress
   ```

2. **Check for failed jobs**
   ```ruby
   SolidQueue::FailedExecution.count
   ```
   Check the error details.

3. **Check logs**
   ```bash
   tail -f log/production.log | grep deliver
   ```

4. **Check DeliveryResponse**
   ```ruby
   DeliveryResponse.where('created_at > ?', 1.hour.ago).group(:status).count
   ```

### Q. Build fails in Docker environment

**Common causes:**

1. **Network unreachable**: Access to rubygems.org and Docker Hub is required
2. **Waiting for DB startup**: After `docker compose up -d`, wait about 60 seconds before running `rails db:migrate`
3. **Port conflict**: Make sure port 3000 is not already in use
