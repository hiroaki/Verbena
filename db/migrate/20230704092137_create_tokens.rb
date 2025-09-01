class CreateTokens < ActiveRecord::Migration[7.0]
  def change
    create_table :tokens do |t|
      t.string :label
      t.string :key_digest_hash

      t.timestamps
    end
    add_index :tokens, :label, unique: true
    add_index :tokens, :key_digest_hash, unique: true
  end
end
