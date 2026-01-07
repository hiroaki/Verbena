(Claude Sonnet 4.5 作成)
---

# バウンス管理機能の設計

## 概要

このドキュメントは将来実装予定の機能について記述したものです。現在のバージョンには含まれていません。

## なぜバウンス管理が必要か

### 現状の制約

Verbenaは現在「SMTP配送先サーバへの引き渡しまで」を保証しますが、以下のケースは検知できません：

- リレー先サーバでのバウンス（5xx恒久エラー、4xx一時エラー）
- スパムフィルタによるドロップ
- メールボックスが満杯で受け取れない
- ユーザーアカウントが存在しない

### バウンス管理によるメリット

1. **配信効率の向上**: 恒久的に配信不能なアドレスへの無駄な再送を回避
2. **スパム判定リスクの軽減**: バウンス率が高いとSMTPサーバの信頼性が低下
3. **運用可視性の向上**: 「どの宛先がなぜ配信不能か」を記録・分析
4. **データ品質の改善**: 無効なアドレスをデータベースから識別・除外

## アーキテクチャ方針

### 単一アプリ構成（Verbenaに統合）

バウンス管理機能はVerbenaに組み込む方針とします。

**理由**:
- システム構成がシンプル（DB・デプロイ・管理が一元化）
- 小〜中規模用途では運用負荷が低い
- 配信時のブラックリストチェックが容易

**将来の拡張性**:
- ブラックリスト部分は疎結合に設計し、必要に応じて切り出し可能にする
- API公開により、他システムからのブラックリスト参照も可能
- Verbenaの配信機能を使わず、ブラックリスト管理だけを利用することも可能

## 段階的実装計画

### Phase 1: 最小構成（手動運用）

配信前チェックと手動管理の基盤を構築します。

**実装内容**:

1. **`bounced_addresses` テーブル**
   ```ruby
   create_table :bounced_addresses do |t|
     t.string :email, null: false, index: { unique: true }
     t.string :reason          # 'user_unknown', 'mailbox_full', 'spam_detected' など
     t.boolean :is_permanent, default: false
     t.datetime :bounced_at
     t.text :details           # バウンスメールの詳細（オプション）
     t.timestamps
   end
   ```

2. **配信前チェック機能**
   - `DeliveryService#perform_one` 内でブラックリストを確認
   - 該当する場合は配送をスキップし、ログに記録
   - スキップしたレコードは `DeliveryResponse` に status 550（またはカスタムコード）で記録

3. **管理画面（Rails Admin / ActiveAdmin 等）**
   - バウンスアドレスの一覧・検索
   - 手動登録・削除
   - 理由（reason）の編集

**ゴール**: 運用者が手動でブラックリストを管理し、配信時に参照できる状態

---

### Phase 2: 自動化（Sisimai統合）

バウンスメールの自動解析とブラックリストへの自動登録を実装します。

**実装内容**:

1. **Sisimaiの導入**
   ```ruby
   # Gemfile
   gem 'sisimai'
   ```

2. **バウンス受信用メールアドレスの設定**
   - 専用のバウンス受信アドレス（例: `bounce@example.com`）を用意
   - 配信時の Return-Path をこのアドレスに統一（または VERP で個別化）

3. **バウンス収集・解析バッチ**
   - cronで定期実行（例: 毎時）
   - IMAP/POP3 または mbox ファイルからバウンスメールを取得
   - Sisimaiで解析し、以下を抽出：
     - バウンスした宛先アドレス
     - エラー理由（reason）
     - 恒久的/一時的エラーの判定（deliverystatus）
   - 恒久的エラー（5xx）は `bounced_addresses` に自動登録
   - 一時的エラー（4xx）は記録のみ（再送ロジックで対応）

4. **Rakeタスク**
   ```bash
   # バウンス収集・解析
   rails verbena:bounce:collect

   # ドライラン（登録せずに解析結果のみ表示）
   rails verbena:bounce:collect[true]
   ```

5. **再送ロジックの改善**
   - 4xxエラーは一定回数・期間まで再送
   - 再送上限に達した場合は管理者通知

**ゴール**: バウンスメールを自動解析し、恒久的エラーアドレスをブラックリストに自動登録

---

### Phase 3: 高度化

外部連携やレポート機能を追加します。

**実装内容**:

1. **ブラックリスト参照API**
   ```ruby
   # GET /api/v1/bounced_addresses?email=test@example.com
   # => { "bounced": true, "reason": "user_unknown", "bounced_at": "..." }
   ```

2. **バウンス統計・レポート**
   - バウンス率の推移グラフ
   - 理由別の集計
   - ドメイン別のバウンス傾向

3. **他システムへの通知**
   - Webhook: バウンス検出時に外部システムへ通知
   - Slack/Email通知: 閾値を超えた場合のアラート

4. **ホワイトリスト機能**
   - 誤検知されたアドレスを除外
   - 一時的にブラックリストを無効化

**ゴール**: エンタープライズ用途でも使える高機能なバウンス管理基盤

## 技術的考慮事項

### Return-Path の設定

バウンスを確実に受信するため、以下の設定が必要です：

**現状の実装**:
```ruby
mail.smtp_envelope_from(mail_queue.envelope_from)
```

**バウンス管理対応**:
```ruby
# 環境変数で指定したバウンス受信用アドレスを使用
bounce_address = ENV['VERBENA_BOUNCE_ADDRESS'] || mail_queue.envelope_from
mail.smtp_envelope_from(bounce_address)
```

または VERP（Variable Envelope Return Path）方式：
```ruby
# 配送ごとにユニークなReturn-Pathを生成
# 例: bounce+12345@example.com (12345 = mail_queue.id)
verp_address = "bounce+#{mail_queue.id}@example.com"
mail.smtp_envelope_from(verp_address)
```

### ブラックリストチェックのタイミング

**推奨**: `DeliveryService#perform_one` 内でチェック

```ruby
def perform_one(mail_queue)
  # ブラックリストチェック
  if BouncedAddress.exists?(email: mail_queue.envelope_to)
    logger.info("Skipped: #{mail_queue.envelope_to} is blacklisted")
    mail_queue.delivery_responses.create!(
      status: 550, # または独自コード 999
      contents: 'Skipped: address is in bounce blacklist',
      responded_at: Time.current
    )
    return
  end

  # ... 既存の配送ロジック
end
```

この方式のメリット：
- スキップしたレコードのログが残る
- 柔軟な判定ロジック（例: 一時エラーは除外、恒久エラーのみブロック）

### Sisimai の使い方（サンプル）

```ruby
# バウンスメール収集・解析サービス
class BounceCollectorService
  def perform
    # IMAP接続（例）
    imap = Net::IMAP.new('imap.example.com', 993, true)
    imap.login('bounce@example.com', 'password')
    imap.select('INBOX')

    # 未読メールを取得
    message_ids = imap.search(['UNSEEN'])

    message_ids.each do |msg_id|
      # メール本文を取得
      msg = imap.fetch(msg_id, 'RFC822')[0].attr['RFC822']

      # Sisimaiで解析
      results = Sisimai.make(msg)
      next if results.nil? || results.empty?

      results.each do |bounce|
        # 恒久的エラー（5xx）のみブラックリスト登録
        if bounce.deliverystatus.start_with?('5.')
          BouncedAddress.find_or_create_by(email: bounce.recipient) do |record|
            record.reason = bounce.reason
            record.is_permanent = true
            record.bounced_at = Time.current
            record.details = bounce.diagnosticcode
          end

          Rails.logger.info("Blacklisted: #{bounce.recipient} (#{bounce.reason})")
        end
      end

      # 既読にする
      imap.store(msg_id, '+FLAGS', [:Seen])
    end

    imap.logout
    imap.disconnect
  end
end
```

## 運用フロー

### 日常運用（Phase 2 以降）

1. cronでバウンス収集バッチを定期実行（毎時）
2. 恒久的エラーアドレスが自動的にブラックリスト登録される
3. 配信時に自動的にスキップされる
4. 管理画面でバウンス状況を確認・手動調整

### トラブルシューティング

- バウンスが正しく解析されない → Sisimai のログを確認、対応MTAを追加
- 誤検知でブラックリスト登録された → 管理画面から削除、またはホワイトリスト機能で除外
- バウンス率が急増 → レポートで原因特定（ドメイン・理由別集計）

## まとめ

バウンス管理機能を段階的に実装することで、Verbenaは「SMTP配送管理」から「実質的な到達性管理」へと進化します。

- **Phase 1**: 最小限の手動管理で即効性
- **Phase 2**: 自動化で運用負荷削減
- **Phase 3**: エンタープライズ用途への対応

単一アプリ構成を維持しつつ、疎結合な設計により将来の拡張性も確保します。
