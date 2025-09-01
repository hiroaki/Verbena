class NormalizationMailQueues < ActiveRecord::Migration[7.0]
  def change
    create_table :eml_sources do |t|
      t.text :eml, null: false
      t.timestamps
    end

    remove_column :mail_queues, :eml, :text, null: false, after: :envelope_to
    add_reference :mail_queues, :eml_source, null: false, foreign_key: true, after: :envelope_to
  end
end
