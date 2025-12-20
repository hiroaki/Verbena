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