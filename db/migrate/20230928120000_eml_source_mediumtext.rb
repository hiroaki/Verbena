# Migration: Change EML column to plain :text for cross-database compatibility.
#
# Note on data storage:
# - This migration uses plain `:text` type across all databases (MySQL/MariaDB, PostgreSQL, SQLite)
#   to ensure portability without adapter-specific options like `limit:` (MySQL-only).
# - On MySQL/MariaDB, Rails `:text` maps to the `TEXT` type, which has a ~64 KiB limit; we accept
#   this as an intentional tradeoff for cross-database compatibility instead of using MEDIUMTEXT/
#   LONGTEXT or MySQL-specific `limit:` options. PostgreSQL and SQLite `text` is effectively
#   unbounded.
# - For future support of large attachments, plan to migrate to object storage (S3, etc.)
#   while storing metadata and small previews in the database.
#
# Note on filename/class name:
# - The class and filename historically referenced "Mediumtext" because the migration
#   originally used a MySQL-specific MEDIUMTEXT mapping. The migration has been
#   updated to use plain `:text` for cross-database compatibility, so the "Mediumtext"
#   suffix is now a historical artifact and does not reflect the current column type.
#   We keep the file as-is to preserve migration timestamps; renaming is optional and
#   purely cosmetic.
class EmlSourceMediumtext < ActiveRecord::Migration[7.0]
  def up
    change_column :eml_sources, :eml, :text, null: false
  end

  def down
    change_column :eml_sources, :eml, :text, null: false
  end
end
