(Created by Claude Sonnet 4.5)
---

# Bounce Management Feature Design

## Overview

This document describes features planned for future implementation. They are not included in the current version.

## Why Bounce Management Is Needed

### Current Limitations

Currently, Verbena guarantees "handoff to the destination SMTP server," but cannot detect the following cases:

- Bounces at relay servers (5xx permanent errors, 4xx temporary errors)
- Drops by spam filters
- Mailbox full and cannot receive
- User account does not exist

### Benefits of Bounce Management

1. **Improved delivery efficiency**: Avoids unnecessary retries to permanently undeliverable addresses
2. **Reduced spam risk**: High bounce rates lower SMTP server reputation
3. **Improved operational visibility**: Records and analyzes "which recipients are undeliverable and why"
4. **Improved data quality**: Identifies and excludes invalid addresses from the database

## Architecture Policy

### Single-App Structure (Integrated into Verbena)

The bounce management feature will be integrated into Verbena.

**Reasons:**
- Simple system structure (DB, deployment, management are unified)
- Low operational burden for small to medium scale use
- Easy blacklist checking at delivery time

**Future extensibility:**
- Design the blacklist part loosely coupled, so it can be separated if needed
- API publication allows other systems to reference the blacklist
- Possible to use only blacklist management without using Verbena's delivery features

## Phased Implementation Plan

### Phase 1: Minimal (Manual Operation)

Build the foundation for pre-delivery checks and manual management.

**Implementation:**

1. **`bounced_addresses` table**
   ```ruby
   create_table :bounced_addresses do |t|
     t.string :email, null: false, index: { unique: true }
     t.string :reason          # 'user_unknown', 'mailbox_full', 'spam_detected', etc.
     t.boolean :is_permanent, default: false
     t.datetime :bounced_at
     t.text :details           # Details of the bounce email (optional)
     t.timestamps
   end
   ```

2. **Pre-delivery check**
   - Check the blacklist in `DeliveryService#perform_one`
   - If matched, skip delivery and log it
   - Skipped records are recorded in `DeliveryResponse` with status 550 (or custom code)

3. **Admin UI (Rails Admin / ActiveAdmin, etc.)**
   - List/search bounced addresses
   - Manual add/delete
   - Edit reason

**Goal**: Operators can manually manage the blacklist and reference it at delivery time

---

### Phase 2: Automation (Sisimai Integration)

Implement automatic parsing of bounce emails and automatic registration to the blacklist.

**Implementation:**

1. **Introduce Sisimai**
   ```ruby
   # Gemfile
   gem 'sisimai'
   ```

2. **Set up bounce receiving email address**
   - Prepare a dedicated bounce receiving address (e.g., `bounce@example.com`)
   - Unify Return-Path at delivery to this address (or individualize with VERP)

3. **Bounce collection/analysis batch**
   - Run periodically with cron (e.g., hourly)
   - Retrieve bounce emails via IMAP/POP3 or from mbox file
   - Parse with Sisimai and extract:
     - Bounced recipient address
     - Error reason
     - Permanent/temporary error determination (deliverystatus)
   - Automatically register permanent errors (5xx) to `bounced_addresses`
   - Record only temporary errors (4xx) (handled by retry logic)

4. **Rake tasks**
   ```bash
   # Collect and analyze bounces
   rails verbena:bounce:collect

   # Dry run (show analysis results only, no registration)
   rails verbena:bounce:collect[true]
   ```

5. **Improve retry logic**
   - Retry 4xx errors up to a certain count/period
   - Notify admin when retry limit is reached

**Goal**: Automatically parse bounce emails and automatically register permanent error addresses to the blacklist

---

### Phase 3: Advanced

Add external integration and reporting features.

**Implementation:**

1. **Blacklist reference API**
   ```ruby
   # GET /api/v1/bounced_addresses?email=test@example.com
   # => { "bounced": true, "reason": "user_unknown", "bounced_at": "..." }
   ```

2. **Bounce statistics/reports**
   - Graph of bounce rate trends
   - Aggregation by reason
   - Bounce trends by domain

3. **Notification to other systems**
   - Webhook: Notify external systems when a bounce is detected
   - Slack/Email notification: Alert when threshold is exceeded

4. **Whitelist feature**
   - Exclude addresses that were falsely detected
   - Temporarily disable blacklist

**Goal**: Highly functional bounce management platform suitable for enterprise use

## Technical Considerations

### Return-Path Setting

To reliably receive bounces, the following settings are required:

**Current implementation:**
```ruby
mail.smtp_envelope_from(mail_queue.envelope_from)
```

**Bounce management support:**
```ruby
# Use bounce receiving address specified by environment variable
bounce_address = ENV['VERBENA_BOUNCE_ADDRESS'] || mail_queue.envelope_from
mail.smtp_envelope_from(bounce_address)
```

Or VERP (Variable Envelope Return Path) method:
```ruby
# Generate a unique Return-Path for each delivery
# Example: bounce+12345@example.com (12345 = mail_queue.id)
verp_address = "bounce+#{mail_queue.id}@example.com"
mail.smtp_envelope_from(verp_address)
```

### Timing of Blacklist Check

**Recommended**: Check inside `DeliveryService#perform_one`

```ruby
def perform_one(mail_queue)
  # Blacklist check
  if BouncedAddress.exists?(email: mail_queue.envelope_to)
    logger.info("Skipped: #{mail_queue.envelope_to} is blacklisted")
    mail_queue.delivery_responses.create!(
      status: 550, # or custom code 999
      contents: 'Skipped: address is in bounce blacklist',
      responded_at: Time.current
    )
    return
  end

  # ... existing delivery logic
end
```

Benefits of this approach:
- Logs skipped records
- Flexible logic (e.g., exclude temporary errors, block only permanent errors)

### How to Use Sisimai (Sample)

```ruby
# Bounce mail collection/analysis service
class BounceCollectorService
  def perform
    # IMAP connection (example)
    imap = Net::IMAP.new('imap.example.com', 993, true)
    imap.login('bounce@example.com', 'password')
    imap.select('INBOX')

    # Get unread emails
    message_ids = imap.search(['UNSEEN'])

    message_ids.each do |msg_id|
      # Get email body
      msg = imap.fetch(msg_id, 'RFC822')[0].attr['RFC822']

      # Parse with Sisimai
      results = Sisimai.make(msg)
      next if results.nil? || results.empty?

      results.each do |bounce|
        # Register only permanent errors (5xx) to blacklist
        if bounce.deliverystatus.start_with?('5.')
          BouncedAddress.find_or_create_by(email: bounce.recipient) do |record|
            record.reason = bounce.reason
            record.is_permanent = true
            record.bounced_at = Time.current
            record.details = bounce.diagnosticcode
          end

          Rails.logger.info("Blacklisted: #{bounce.recipient} (#{bounce.reason})")
        end
      end

      # Mark as read
      imap.store(msg_id, '+FLAGS', [:Seen])
    end

    imap.logout
    imap.disconnect
  end
end
```

## Operational Flow

### Daily Operation (Phase 2 and later)

1. Run bounce collection batch periodically with cron (hourly)
2. Permanent error addresses are automatically registered to the blacklist
3. Automatically skipped at delivery time
4. Check and manually adjust bounce status in the admin UI

### Troubleshooting

- Bounce not parsed correctly → Check Sisimai logs, add supported MTA
- Falsely blacklisted → Remove from admin UI or exclude with whitelist feature
- Sudden increase in bounce rate → Identify cause with reports (aggregate by domain/reason)

## Summary

By implementing the bounce management feature in phases, Verbena will evolve from "SMTP delivery management" to "practical deliverability management."

- **Phase 1**: Immediate effect with minimal manual management
- **Phase 2**: Reduced operational burden through automation
- **Phase 3**: Support for enterprise use

While maintaining a single-app structure, loosely coupled design ensures future extensibility.
