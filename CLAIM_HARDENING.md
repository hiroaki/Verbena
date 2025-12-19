# MailQueue.claim! Hardening Implementation

This document describes the enhanced `MailQueue.claim!` implementation that provides robust concurrent execution safety and automatic stale record recovery.

## Overview

The original `claim!` method used a simple `update_all` operation that could cause race conditions in concurrent environments. The enhanced implementation addresses these issues through:

1. **Atomic Batch Processing**: Uses small batches by first selecting IDs then updating by ID set to reduce lock contention
2. **Deadlock Recovery**: Implements exponential backoff with full jitter for deadlock scenarios (defaults: base=1s, cap=300s; expected wait ranges per attempt: 0–1s, 0–2s, 0–4s, 0–8s, 0–16s, ...)
3. **Stale Detection**: Tracks claim time with `claimed_at` column for automatic recovery
4. **Monitoring Tools**: Provides rake tasks for maintenance and monitoring

## Database Changes

### Migration: `20250902120000_add_claimed_at_to_mail_queues.rb`

```ruby
class AddClaimedAtToMailQueues < ActiveRecord::Migration[7.1]
  def change
    add_column :mail_queues, :claimed_at, :datetime
    
    # Add indexes for efficient querying during claim operations
    add_index :mail_queues, :session_id
    add_index :mail_queues, :claimed_at
    add_index :mail_queues, [:session_id, :claimed_at]
    add_index :mail_queues, [:timer_at, :session_id]
  end
end
```

**New Column:**
- `claimed_at`: Records when a record was claimed by a session. Used for stale detection.

**New Indexes:**
- `session_id`: Speeds up session-based queries
- `claimed_at`: Enables efficient stale record detection  
- `session_id + claimed_at`: Composite index for session cleanup
- `timer_at + session_id`: Optimizes timer-based claim queries

## Enhanced Model Methods

### Core Claiming Logic

The enhanced `claim!` method now:

1. **Processes in small batches** (default 20 records) to reduce lock duration
2. **Retries on deadlock** with exponential backoff (5s, 15s, 30s, 1m, 3m, 5m+)
3. **Sets `claimed_at`** timestamp for stale detection
4. **Uses atomic operations** to prevent race conditions

```ruby
# Internal method - processes claims in batches
# Select IDs in small batches, then update by ID set
# Timestamps:
# - claimed_at: per-session consistent timestamp
# - updated_at: set via Time.current when updating

def self.claim_in_batches(session_id, condition)
  batch_size   = claim_batch_size
  max_retries  = claim_max_retries
  total_claimed = 0
  current_time = Time.current

  retries = 0

  loop do
    ids = where(condition.merge(session_id: nil)).order(:id).limit(batch_size).pluck(:id)
    break if ids.empty?

    begin
      claimed_count = where(id: ids, session_id: nil).update_all(
        session_id: session_id,
        claimed_at: current_time,
        updated_at: Time.current
      )

      total_claimed += claimed_count
      break if ids.length < batch_size
      retries = 0
    rescue ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout => e
      if retries < max_retries
        backoff_seconds = calculate_backoff_seconds(retries)
        Rails.logger.warn("[MailQueue] Deadlock detected, retrying in #{backoff_seconds}s")
        sleep(backoff_seconds)
        retries += 1
        next
      else
        Rails.logger.error("[MailQueue] Max retries exceeded: #{e.message}")
        raise
      end
    end
  end

  total_claimed
end
```

### Stale Record Management

```ruby
# Release claims older than specified time (default: 1 hour)
def self.release_stale_claims!(older_than: 1.hour.ago)
  stale_count = where.not(claimed_at: nil)
                .where(claimed_at: ..older_than)
                .where.not(session_id: nil)
                .update_all(session_id: nil, claimed_at: nil, updated_at: Time.current)
  
  Rails.logger.info("[MailQueue] Released #{stale_count} stale claims") if stale_count > 0
  stale_count
end

# Find records that are claimed but have no delivery results (stuck processing)
def self.claimed_but_undelivered
  left_outer_joins(:delivery_responses)
    .where.not(session_id: nil)
    .where(delivery_responses: { id: nil })
end
```

## Rake Tasks

### Stale Claim Cleanup

```bash
# Release stale claims older than 1 hour (dry run)
rails verbena:claim:release_stale[1,dry]

# Release stale claims older than 2 hours (execute)  
rails verbena:claim:release_stale[2]

# Show currently stale claimed records
rails verbena:claim:show_stale
```

### Example Output

```bash
$ rails verbena:claim:show_stale
Found 3 claimed but undelivered records:
ID      Session ID      Claimed At              Envelope To             Age
--------------------------------------------------------------------------------
1001    abc12345...     2023-10-23 10:15:22     user@example.com        2h15m30s
1002    def67890...     2023-10-23 11:30:45     admin@example.com       1h0m15s
1003    ghi54321...     2023-10-23 12:00:12     support@example.com     30m48s
```

## Configuration

### Batch Size

The claim batch size is controlled by the existing `VERBENA_IN_BATCHES_OF` environment variable:

```bash
# .env file
VERBENA_IN_BATCHES_OF=100  # Default batch size for delivery processing
```

For claim operations, a smaller default (20) is used to reduce lock contention, but it respects the environment setting.

### Retry Configuration

The retry logic is built-in with exponential backoff and full jitter:

- **Max retries**: Configurable via `VERBENA_CLAIM_MAX_RETRIES` (default 5). The value counts retries; you get one initial attempt plus up to this many retries.
- **Backoff strategy**: `base * 2^retry_count` capped at `cap`, with full jitter in `[0, maxDelay]` (defaults: base=1s, cap=300s). Approximate wait ranges: 0–1s, 0–2s, 0–4s, 0–8s, 0–16s, etc.
- **Exception handling**: `ActiveRecord::Deadlocked`, `ActiveRecord::LockWaitTimeout`

## Deployment Guide

### 1. Deploy Migration

```bash
rails db:migrate
```

### 2. Add Cron Job for Stale Cleanup

Add to your crontab or deployment scheduler:

```bash
# Run every 30 minutes to clean up stale claims older than 1 hour
*/30 * * * * cd /path/to/verbena && bin/rails verbena:claim:release_stale[1] >> log/stale_cleanup.log 2>&1
```

### 3. Monitoring

Set up monitoring for stuck processing:

```bash
# Daily check for long-running claims
0 9 * * * cd /path/to/verbena && bin/rails verbena:claim:show_stale >> log/stale_monitoring.log 2>&1
```

## Testing

### Unit Tests

The implementation includes comprehensive tests for:

- **Basic functionality**: Existing claim behavior preserved
- **Concurrency safety**: Multiple sessions cannot claim the same records
- **Batch processing**: Large sets are processed in chunks
- **Stale cleanup**: Old claims are properly released
- **Edge cases**: Deadlock recovery, empty result sets

### Example Test

```ruby
it '重複して claim されない（基本的な排他制御テスト）' do
  session_id_1 = MailQueue.issue_session_id
  session_id_2 = MailQueue.issue_session_id
  
  # 最初のセッションで claim
  claimed_count_1 = MailQueue.claim_by_timer!(session_id_1)
  
  # 2番目のセッションで claim を試行（残りがあれば取得）
  claimed_count_2 = MailQueue.claim_by_timer!(session_id_2)
  
  # 合計が元のレコード数と一致
  expect(claimed_count_1 + claimed_count_2).to eq(available_records.length)
  
  # それぞれのセッションで取得したレコードに重複がない
  session_1_ids = MailQueue.claimed(session_id_1).pluck(:id)
  session_2_ids = MailQueue.claimed(session_id_2).pluck(:id)
  expect(session_1_ids & session_2_ids).to be_empty
end
```

## Performance Considerations

### MySQL Optimization

The implementation is optimized for MySQL:

- **Small batches**: Reduces lock duration and contention
- **Efficient indexes**: Supports fast lookups for claim operations
- **LIMIT clause**: Prevents full table scans
- **Proper WHERE conditions**: Uses indexed columns effectively

### Production Recommendations

1. **Monitor deadlock frequency**: Increase batch size if deadlocks are rare
2. **Adjust stale timeout**: Balance between recovery speed and false positives
3. **Database connections**: Ensure adequate connection pool for concurrent claiming
4. **Logging**: Monitor claim operation logs for performance issues

## Migration from Old Implementation

The new implementation is **backward compatible**:

- **Existing behavior preserved**: All public APIs work the same way
- **Gradual rollout**: Can be deployed without changing calling code
- **Performance improvement**: Should see reduced deadlocks and better throughput
- **Automatic cleanup**: Stale records will be automatically recovered

### Breaking Changes: None

The enhancement maintains full API compatibility while improving internal implementation robustness.

## Troubleshooting

### Common Issues

1. **High deadlock frequency**
   - **Cause**: Batch size too large or high concurrency
   - **Solution**: Reduce `VERBENA_IN_BATCHES_OF` or increase staggered execution

2. **Stale records accumulating**
   - **Cause**: Cron job not running or timeout too long
   - **Solution**: Check cron schedule and reduce stale timeout

3. **Slow claim operations**
   - **Cause**: Missing indexes or large batch size
   - **Solution**: Verify indexes exist and reduce batch size

### Debug Commands

```bash
# Check for current claimed records
rails runner "puts MailQueue.where.not(session_id: nil).count"

# Check for stale records
rails runner "puts MailQueue.where('claimed_at < ?', 1.hour.ago).count"

# Manual stale cleanup (dry run)
rails verbena:claim:release_stale[1,dry]
```