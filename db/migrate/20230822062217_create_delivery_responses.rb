class CreateDeliveryResponses < ActiveRecord::Migration[7.0]
  def change
    create_table :delivery_responses do |t|
      t.string :delivery_method
      t.references :mail_queue, null: false, foreign_key: true
      t.datetime :responded_at
      t.string :status
      t.string :contents

      t.timestamps
    end
  end
end
