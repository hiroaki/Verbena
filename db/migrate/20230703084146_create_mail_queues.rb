class CreateMailQueues < ActiveRecord::Migration[7.0]
  def change
    create_table :mail_queues do |t|
      t.string :session_id
      t.string :subject
      t.string :mail_to
      t.string :mail_cc
      t.string :mail_bcc
      t.string :mail_from
      t.text :mail_body
      t.datetime :timer_at

      t.timestamps
    end
  end
end
