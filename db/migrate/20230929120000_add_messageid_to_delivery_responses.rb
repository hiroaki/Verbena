class AddMessageidToDeliveryResponses < ActiveRecord::Migration[7.0]
  def change
    remove_column :delivery_responses, :delivery_method, :string

    add_column :delivery_responses, :message_id, :string
  end
end
