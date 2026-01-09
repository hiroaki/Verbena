class ChangeMailQueuesPrototype2 < ActiveRecord::Migration[7.0]
  def change
    remove_column :mail_queues, :subject, :string
    remove_column :mail_queues, :mail_to, :string
    remove_column :mail_queues, :mail_cc, :string
    remove_column :mail_queues, :mail_bcc, :string
    remove_column :mail_queues, :mail_from, :string
    remove_column :mail_queues, :mail_body, :string

    add_column :mail_queues, :envelope_from, :string
    add_column :mail_queues, :envelope_to, :string, null: false
    add_column :mail_queues, :eml, :text, null: false
  end
end
