class AddDeliveryStateToMailQueues < ActiveRecord::Migration[7.1]
  def change
    add_column :mail_queues, :delivery_status, :string, null: false, default: 'pending'
    add_column :mail_queues, :locked_until, :datetime
    add_column :mail_queues, :attempts_count, :integer, null: false, default: 0
    add_column :mail_queues, :last_attempted_at, :datetime

    add_index :mail_queues, :delivery_status

    reversible do |dir|
      dir.up do
        # バックフィル方針:
        # - マイグレーション内ではアプリケーションのモデルを読み込まず、単純で安全な SQL を使います。
        # - ここでは既に `delivery_responses` を持つ既存の `mail_queues` を一時的に
        #   `delivery_status = 'migrate'` とマークします。自動で成功/失敗を判定すると誤判定の恐れがあるため、
        #   移行対象として明示し、運用側で個別に確認・再分類してください。
        # - 将来的に自動分類を行う場合は、`delivery_responses` に適切なインデックスを追加し、
        #   DB 側で最新レスポンスを効率的に取得して 2xx/4xx/5xx で振り分けるバッチを検討してください。
        say_with_time("Backfilling delivery_status => 'migrate' for mail_queues with responses") do
          execute <<~SQL.squish
            UPDATE mail_queues
            SET delivery_status = 'migrate'
            WHERE EXISTS (
              SELECT 1 FROM delivery_responses dr WHERE dr.mail_queue_id = mail_queues.id
            )
          SQL
        end
      end
    end
  end
end
