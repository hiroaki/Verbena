class AddTokenSecurityFields < ActiveRecord::Migration[7.1]
  # Minimal AR model to avoid app-layer callbacks/validations in migration
  class MToken < ActiveRecord::Base
    self.table_name = 'tokens'
  end

  def up
    add_column :tokens, :expires_at, :datetime, null: true
    add_column :tokens, :revoked_at, :datetime, null: true
    add_column :tokens, :last_used_at, :datetime, null: true

    add_index :tokens, :expires_at
    add_index :tokens, :revoked_at

    # Backfill expires_at for existing rows to a far future to keep them valid by default
    now = Time.current
    future_default = now + 10.years
    MToken.reset_column_information
    MToken.where(expires_at: nil).update_all(expires_at: future_default)

    change_column_null :tokens, :expires_at, false
  end

  def down
    remove_index :tokens, :expires_at
    remove_index :tokens, :revoked_at
    remove_column :tokens, :last_used_at
    remove_column :tokens, :revoked_at
    remove_column :tokens, :expires_at
  end
end
