class AddTokenIdToMailQueues < ActiveRecord::Migration[8.1]
  # マイグレーション内でモデルを参照するために一時的なクラスを定義
  class MigrationToken < ActiveRecord::Base
    self.table_name = :tokens
  end

  class MigrationMailQueue < ActiveRecord::Base
    self.table_name = :mail_queues
  end

  def up
    # 1. まずは null: true でカラムを追加
    add_reference :mail_queues, :token, null: true, foreign_key: { on_delete: :restrict }

    # 2. 既存データがある場合のみ、紐付け用のトークンを用意して更新
    if MigrationMailQueue.exists?
      now = Time.current
      token = MigrationToken.find_by(label: 'System Access (Migration)')
      unless token
        token = MigrationToken.create!(
          key_digest_hash: "migration-dummy-hash-#{SecureRandom.hex(16)}",
          label: 'System Access (Migration)',
          created_at: now,
          updated_at: now,
          expires_at: 10.years.from_now # 十分な未来
        )
      end

      # 既存の全 MailQueue レコードにトークンを紐付ける
      MigrationMailQueue.update_all(token_id: token.id)
    end

    # 3. 最後に not null 制約を適用
    change_column_null :mail_queues, :token_id, false
  end

  def down
    remove_reference :mail_queues, :token
  end
end
