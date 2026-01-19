class AddDeliveryStateToMailQueues < ActiveRecord::Migration[7.1]
  def change
    add_column :mail_queues, :delivery_status, :string, null: false, default: 'pending'
    add_column :mail_queues, :locked_until, :datetime
    add_column :mail_queues, :attempts_count, :integer, null: false, default: 0
    add_column :mail_queues, :last_attempted_at, :datetime

    add_index :mail_queues, :delivery_status

    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          UPDATE mail_queues
          SET delivery_status = 'succeeded'
          WHERE EXISTS (
            SELECT 1 FROM delivery_responses dr
            WHERE dr.mail_queue_id = mail_queues.id
          )
        SQL
      end
    end
  end
end
