class RemoveSessionIdFromMailQueues < ActiveRecord::Migration[7.1]
  def change
    # Destructive removal of session_id and related indexes.
    # This repository is not yet released and data migration is not required.
    if index_exists?(:mail_queues, [:session_id, :claimed_at])
      remove_index :mail_queues, column: [:session_id, :claimed_at]
    end

    if index_exists?(:mail_queues, [:timer_at, :session_id])
      remove_index :mail_queues, column: [:timer_at, :session_id]
    end

    if index_exists?(:mail_queues, :session_id)
      remove_index :mail_queues, column: :session_id
    end

    remove_column :mail_queues, :session_id, :string, if_exists: true
  end
end
