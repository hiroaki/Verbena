(GPT-5 によるプラン作成)
---

# Issue 10: Rails と DB のタイムゾーン統一（UTC）改善計画

## 概要
- 目的: 本番・テスト環境でアプリと DB の時刻扱いを完全に UTC に統一し、時刻比較の再現性を担保する。
- 対象: Rails 設定、DB コンテナの OS タイムゾーン、DB セッションタイムゾーン、README の方針明記、必要に応じたテスト追加。

## 現状確認（Findings）
- Rails 側は既に UTC を使用:
  - [config/application.rb](config/application.rb#L34-L36) にて `config.time_zone = "UTC"` と `config.active_record.default_timezone = :utc`。
- DB は MariaDB (mysql2 アダプタ):
  - [config/database.yml](config/database.yml) で `adapter: mysql2`、ホスト `db`。
  - [compose.yml](compose.yml#L4-L15) の `db` サービス環境変数 `TZ: Asia/Tokyo`（コンテナ OS 時刻が JST）。
- SQL 時刻関数の使用状況:
  - [app/models/delivery_response.rb](app/models/delivery_response.rb#L46) で `ADDTIME` を使用（`NOW()` は未使用）。
  - `ADDTIME` は既存の `datetime` 値に対する演算であり、セッション TZ の影響は限定的（`NOW()` を避ければ再現性は高い）。

## 問題点
- コンテナ OS TZ が JST であるため、DB の `SYSTEM` ベースな時刻参照やログ等と UTC 前提の Rails との間で認知的不一致を生む可能性。
- DB セッション TZ が環境により UTC である保証がないと、`NOW()` 等をもし使用した場合に不一致が発生し得る。

## 方針（Decision）
1. コンテナ OS のタイムゾーンを UTC に統一。
   - `compose.yml` の `db.environment.TZ` を `UTC` に変更。
2. DB セッションタイムゾーンを接続ごとに UTC へ固定。
   - `mysql2` の `init_command` で `SET time_zone = '+00:00'` を実行（全環境）。
3. SQL の `NOW()`/`CURRENT_TIMESTAMP` を比較に使わないガイドラインを維持。
   - 比較用時刻は Ruby 側で生成し、バインドパラメータとして渡す。
4. README に「UTC 前提」を明記し、運用者向けに Compose と DB セッション固定の説明を追加。
5. テストでの担保を強化。
   - 可能であれば DB 接続があるテストにて `TIMEDIFF(NOW(), UTC_TIMESTAMP()) = '00:00:00'` を検証（integration / optional）。

## 実装ステップ（Plan）
- Step A: Compose の TZ を UTC に変更。
  - ファイル: [compose.yml](compose.yml)
  - 変更: `db.environment.TZ: Asia/Tokyo` → `UTC`
- Step B: ActiveRecord 接続時にセッション TZ を UTC に固定。
  - ファイル: [config/database.yml](config/database.yml)
  - 追加案: `default:` セクションへ `init_command: "SET time_zone = '+00:00'"`
- Step C: SQL 時刻関数の使用監査とコーディング規約明文化。
  - ファイル: [app/models/delivery_response.rb](app/models/delivery_response.rb) 他
  - 現状 `NOW()` 非使用を維持。もし他所で `NOW()` を発見時は Ruby 時刻へ置換。
- Step D: README を更新（UTC 前提の明記と手順）。
  - ファイル: [README.md](README.md)
  - 追記: "Verbena はアプリ/DB とも UTC 前提"、Compose で `TZ=UTC`、DB セッション固定の記述。
- Step E: テスト追加（任意/統合）。
  - ファイル: [spec/config/timezone_spec.rb](spec/config/timezone_spec.rb)
  - 追加: DB 接続が可能な場合に限り、`TIMEDIFF(NOW(), UTC_TIMESTAMP())` が `00:00:00` であることを検証。

## 他 DB への拡張（将来対応）
- PostgreSQL: `config/database.yml` の各環境で `variables: { timezone: 'UTC' }` を指定する。`init_command` 相当の `SET TIME ZONE 'UTC'` を使う場合でも、アダプタの `variables` 設定を優先。
- SQLite: Rails が UTC で扱う前提を維持し、SQLite の SQL 時刻関数（`datetime('now')` 等）を比較に使わない。比較時刻は Ruby 側で生成してバインドする。
- MySQL/MariaDB: 本計画どおり `init_command: "SET time_zone = '+00:00'"` を採用し、TZ テーブル要件を回避。

## 受け入れ基準（Acceptance Criteria）
- Rails の `Time.zone` と `ActiveRecord.default_timezone` が UTC である（既存テストが通る）。
- Compose 経由で起動した DB コンテナの OS TZ が UTC。
- ActiveRecord 経由の各環境接続で、DB セッション TZ が UTC に固定される。
- 時刻比較を含むテストが環境差により落ちなくなる（`NOW()` 非使用を確認）。
- README に UTC 前提が明記される。

## リスク / 注意事項
- MariaDB の `time_zone` 設定は `'+00:00'` を使うと TZ テーブルなしでも機能するが、`'UTC'` を使う場合はシステム TZ テーブルが必要な構成がある。実装では `'+00:00'` を採用。
- `datetime` 型は TZ 非依存だが、`timestamp` 型はセッション TZ 変換が入るため、将来のスキーマ変更時は型選定に留意。
- 既存コードで `NOW()` を使っていないが、新規開発時も Ruby 時刻生成（`Time.current` 等）＋バインドで統一する。

## ロールアウト手順（例）
1. `compose.yml` を更新し `TZ=UTC` に変更。
2. `config/database.yml` に `init_command` を追加して DB セッション TZ を UTC へ固定。
3. 影響コードの監査（`NOW()` 使用がないことの確認）。
4. README 更新、必要なテスト追加。
5. 開発・CI・本番で動作確認（ログ・簡易クエリなど）。

