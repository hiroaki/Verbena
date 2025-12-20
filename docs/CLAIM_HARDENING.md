(GPT-4.1 作成)
---

# MailQueue.claim! Hardening Implementation

This document describes the enhanced `MailQueue.claim!` implementation that provides robust concurrent execution safety and automatic stale record recovery.

## Overview

The original `claim!` method used a simple `update_all` operation that could cause race conditions in concurrent environments. The enhanced implementation addresses these issues through:

1. **Atomic Batch Processing**: Uses small batches by first selecting IDs then updating by ID set to reduce lock contention
2. **Deadlock Recovery**: Implements exponential backoff with full jitter for deadlock scenarios (defaults: base=1s, cap=300s; maximum possible wait ranges per attempt with randomization: 0–1s, 0–2s, 0–4s, 0–8s, 0–16s, ...)
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
2. **Retries on deadlock** with exponential backoff and full jitter (configurable via `VERBENA_CLAIM_BACKOFF_BASE_SECONDS` and `VERBENA_CLAIM_BACKOFF_CAP_SECONDS`; defaults: base=1s, cap=300s)
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

### Implementation Details: Batch Claim Strategy

#### Why ID-first approach instead of LIMIT + update_all?

**Previous approach problems (LIMIT + update_all pattern)**:
- `where(...).limit(n).update_all(...)` is database-adapter dependent:
  - Works in MySQL with `UPDATE ... LIMIT n` syntax
  - Not supported in PostgreSQL and other databases
  - Breaks cross-database compatibility
- ORM-level `update_all` with `LIMIT` may not restrict rows as expected:
  - Silent behavior differences (fewer/more rows updated than intended)
  - Can update all rows instead of limited subset
- UPDATE with LIMIT can be a deadlock hotspot due to varying lock strategies across databases

**Current approach (fetch IDs first, then update by ID set)**:
1. First SELECT a small batch of record IDs using `pluck(:id)`
2. Then execute `update_all` with `WHERE id IN (...)` on those specific IDs

**Advantages**:
- **Portable**: Works across PostgreSQL, MySQL, and other major database adapters
- **Predictable**: Explicitly updates a specific set of IDs, consistent behavior across adapters
- **Verifiable**: `update_all` return value shows actual rows updated, enabling sanity checks

**TOCTOU and Race Condition Handling**:
- There is a TOCTOU (time-of-check-to-time-of-use) window between `pluck` and `update_all`
- Multiple processes may `pluck` the same IDs and attempt concurrent updates
- **However**: The `update_all` WHERE clause includes `session_id: nil` guard condition
  - Only one process can successfully set `session_id` for each record
  - Records already claimed by another process won't be counted in the update
  - Effectively prevents duplicate claims without explicit row locks

**Why not SELECT ... FOR UPDATE?**:
- SELECT ... FOR UPDATE provides complete race prevention but has trade-offs:
  - **Performance**: Holds locks longer, reducing throughput
  - **Portability**: Lock syntax and semantics vary across databases
  - **Scalability**: More prone to lock waits and deadlocks under high concurrency
- The current approach using `session_id: nil` guard achieves:
  - **Short lock duration**: Minimal lock holding time
  - **Low deadlock rate**: Rarely causes deadlocks even under high parallelism
  - **Good scalability**: Better throughput in high-concurrency environments
  - **Logical exclusivity**: Achieves exclusive update through WHERE conditions
  - **Practical balance**: Sufficient safety, portability, and scalability for production use

### Stale Record Management

```ruby
# Release claims older than specified time (default: 1 hour)
def self.release_stale_claims!(older_than: 1.hour.ago)
  stale_count = where(claimed_at: ..older_than)
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

- **Max retries**: Configurable via `VERBENA_CLAIM_MAX_RETRIES` (default 5). This value is the number of *retry attempts* after the initial attempt. The counter is 0-based and the code uses `retries < max_retries`, which allows exactly `max_retries` retries. Therefore, the total number of attempts is `max_retries + 1` (e.g., 5 → 1 initial attempt + up to 5 retries = 6 total attempts).
  - Note: Log messages display the retry attempt number as `attempt N/max_retries` (e.g., `attempt 1/5` for the first retry). This denominator refers to the configured maximum number of retries and does not include the initial attempt.
- **Backoff strategy**: `base * 2^retry_count` capped at `cap`. Full jitter is applied (wait = `rand * max_delay`, where `rand ∈ [0, 1)`). Defaults: base=1s, cap=300s. The listed ranges (0–1s, 0–2s, ...) are the maximum possible waits per attempt; the actual wait is a uniformly random value in `[0, max_delay)`.
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
it 'does not claim the same record twice (basic mutual exclusion test)' do
  session_id_1 = MailQueue.issue_session_id
  session_id_2 = MailQueue.issue_session_id

  # Claim with the first session
  claimed_count_1 = MailQueue.claim_by_timer!(session_id_1)

  # Attempt to claim with the second session (should get remaining records if any)
  claimed_count_2 = MailQueue.claim_by_timer!(session_id_2)

  # The total should match the original number of available records
  expect(claimed_count_1 + claimed_count_2).to eq(available_records.length)

  # There should be no overlap between records claimed by each session
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

## Max Retries Exceeded: Recovery Procedures

When the maximum retry count is exceeded during claim operations (after encountering repeated deadlocks), the operation will log an error and raise an exception. This is an exceptional situation that requires operational intervention.

### Recommended Operational Response

1. **First, log the affected records**: Collect a sample of IDs and the total count of records updated with the problematic `session_id`
2. **Do not automatically clear immediately**: Recovery should be executed with human judgment rather than automatic cleanup
3. **Implement recovery with the following safety policies**:
   - **Limit scope**: Only target records that are "undelivered (no delivery_responses) AND have sufficiently old claimed_at timestamps"
   - **Enable dry-run**: Allow verification of which records will be affected before execution
   - **Maintain execution logs**: Record who executed the recovery, how many records, and which session_id

### Manual Recovery Example

If you need to manually recover stuck records from a specific session:

```ruby
# Example: Clear claims for undelivered records older than 5 minutes
MailQueue.left_outer_joins(:delivery_responses)
         .where(session_id: problem_session_id)
         .where(delivery_responses: { id: nil })
         .where('claimed_at < ?', 5.minutes.ago)
         .update_all(session_id: nil, claimed_at: nil, updated_at: Time.current)
```

### Future Automation via Rake Task

For future enhancement, a rake task can be implemented (with manual trigger requirement):

- **Task name example**: `verbena:claim:recover[SESSION_ID,only_undelivered,older_than,dry_run]`
- **Options**: `--dry-run`, `only_undelivered=true/false`, `older_than=5.minutes`
- **Workflow**: Display dry-run results first, then allow execution after confirmation
- **Testing**: Include unit tests (recover method) and rake task integration tests

### Current Implementation

Currently, the code only logs the error and re-raises the exception, delegating recovery decisions to the caller (operator):

```ruby
Rails.logger.error("[MailQueue] Max retries exceeded for claim operation for session_id=[#{session_id}]: #{e.message}")
raise
```

This design ensures that critical situations requiring manual intervention are not automatically resolved, preventing potential data loss or incorrect state transitions.

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