class AddIndexesForPerformance < ActiveRecord::Migration[7.1]
  def change
    # For deadline queries on mail_queues (e.g., WHERE timer_at <= NOW())
    unless index_exists?(:mail_queues, :timer_at)
      add_index :mail_queues, :timer_at
    end

    # For fetching the latest delivery response per mail_queue efficiently
    unless index_exists?(:delivery_responses, [:mail_queue_id, :responded_at])
      add_index :delivery_responses, [:mail_queue_id, :responded_at]
    end
  end
end
