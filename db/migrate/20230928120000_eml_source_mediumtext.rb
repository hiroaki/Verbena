class EmlSourceMediumtext < ActiveRecord::Migration[7.0]
  def up
    change_column :eml_sources, :eml, :text, limit: 16777215, null: false
  end

  def down
    change_column :eml_sources, :eml, :text, null: false
  end
end
