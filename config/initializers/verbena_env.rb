# Validate and prepare Verbena runtime from environment variables.
#
# TODO(per-setting validation): 将来的に設定項目ごとに個別の検証関数を用意し、この初期化子で順に呼び出す形へ移行する。
# 例:
#   validate_delivery_method!(value)
#   validate_smtp_address!(value)
#   validate_smtp_port!(value)
#   validate_smtp_authentication!(value)
#   validate_parallel_concurrency!(value)
#   validate_in_batches_of!(value)
# など。これにより、任意の箇所で単一項目の検証を再利用でき、ルールの重複や網羅性不足を防げる。
#
# TODO(other concerns):
# - エラー処理の統一: abort の使用をやめ、専用例外（例: Verbena::ConfigurationError）とログ出力へ統一。
# - ログ方針: 起動時に非機密の設定サマリを info で出す（パスワード等は伏せる）。
# - 正規化/型変換: ENV のトリム/数値/真偽の正規化を明示化し、不正値は既定値へフォールバックまたは起動失敗。
# - 本番での固定化: Settings を configure 後に freeze して再設定を防止（開発は to_prepare で毎回再構成）。
# - 読み込み順序: Settings 依存の他初期化子よりも先に実行されるようにファイル名/ロード順を調整。
# - to_prepare の実行回数: 開発ではリロード毎に実行される。副作用（ディレクトリ作成等）は冪等であることを確認/最適化。

Rails.application.config.to_prepare do
  # Read raw ENV here to avoid coupling the boot-time initializer to runtime settings accessors.
  delivery_method = ENV['VERBENA_DELIVERY_METHOD'].to_s.strip.downcase
  delivery_method = Rails.env.production? ? 'smtp' : 'test' if delivery_method.blank?

  # Configure runtime settings singleton with the resolved settings (block style)
  Verbena::Settings.configure do |c|
    c.delivery_method = delivery_method
    # SMTP
    c.smtp_address = ENV['VERBENA_DELIVERY_SMTP_ADDRESS']
    c.smtp_port = ENV['VERBENA_DELIVERY_SMTP_PORT']
    c.smtp_domain = ENV['VERBENA_DELIVERY_SMTP_DOMAIN']
    c.smtp_user_name = ENV['VERBENA_DELIVERY_SMTP_USER_NAME']
    c.smtp_password = ENV['VERBENA_DELIVERY_SMTP_PASSWORD']
    c.smtp_authentication = ENV['VERBENA_DELIVERY_SMTP_AUTHENTICATION']
    c.smtp_enable_starttls_auto = ENV['VERBENA_DELIVERY_SMTP_ENABLE_STARTTLS_AUTO']

    # Envelope-from override (optional)
    c.envelope_from_override = ENV['VERBENA_ENVELOPE_FROM_OVERRIDE']

    # File delivery
    c.file_delivery_dir = ENV['VERBENA_FILE_DELIVERY_DIR']

    # API pagination (defaults with ENV overrides)
    c.api_pagination_default_limit = ENV['VERBENA_API_PAGINATION_DEFAULT_LIMIT']
    c.api_pagination_limit_cap = ENV['VERBENA_API_PAGINATION_LIMIT_CAP']
    c.api_pagination_default_offset = ENV['VERBENA_API_PAGINATION_DEFAULT_OFFSET']

    # API responses include limits
    c.api_responses_default_limit = ENV['VERBENA_API_RESPONSES_DEFAULT_LIMIT']
    c.api_responses_limit_cap = ENV['VERBENA_API_RESPONSES_LIMIT_CAP']

    # General limits
    c.eml_max_bytes = ENV['VERBENA_EML_MAX_BYTES']

    # Cleanup TTL (days) — assign raw ENV; normalization happens in Settings reader
    c.cleanup_ttl_days = ENV['VERBENA_CLEANUP_TTL_DAYS']

    # Delivery retry attempts
    c.delivery_max_retries = ENV['VERBENA_DELIVERY_MAX_RETRIES']

    # Delivery lock TTLs
    c.delivery_lock_ttl_seconds = ENV['VERBENA_DELIVERY_LOCK_TTL_SECONDS']
    c.delivery_lock_max_seconds = ENV['VERBENA_DELIVERY_LOCK_MAX_SECONDS']

    # Admin authentication
    c.admin_username = ENV['VERBENA_ADMIN_USERNAME']
    c.admin_password = ENV['VERBENA_ADMIN_PASSWORD']
  end

  case delivery_method
  when 'smtp'
    required = %w[
      VERBENA_DELIVERY_SMTP_ADDRESS
      VERBENA_DELIVERY_SMTP_PORT
      VERBENA_DELIVERY_SMTP_DOMAIN
      VERBENA_DELIVERY_SMTP_AUTHENTICATION
      VERBENA_DELIVERY_SMTP_USER_NAME
      VERBENA_DELIVERY_SMTP_PASSWORD
    ]
    missing = required.select { |k| ENV[k].blank? }
    if missing.any?
      abort "[Verbena] Missing required ENV for SMTP: #{missing.join(', ')}"
    end
  when 'file'
    dir = ENV['VERBENA_FILE_DELIVERY_DIR'].presence || Rails.root.join('tmp', 'mails').to_s
    begin
      FileUtils.mkdir_p(dir)
    rescue => e
      abort "[Verbena] Failed to prepare file delivery dir: #{dir} (#{e.class}: #{e.message})"
    end
  end
end
