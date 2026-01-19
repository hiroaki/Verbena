module Verbena
  # Centralized application settings accessor (singleton-like via class methods).
  #
  # Overview
  # - Settings are configured at boot in an initializer using either a hash or a block DSL.
  # - Consumers should only read through these accessors; do not read ENV directly.
  # - Tests can stub these class methods or use `reset!` to control behavior without mutating ENV.
  #
  # delivery_method
  # - One of :smtp, :test, :file.
  # - Default: :smtp in production, :test in other environments.
  # - Can be set via:
  #     Verbena::Settings.configure(delivery_method: :file)
  #   or
  #     Verbena::Settings.configure { |c| c.delivery_method = :file }
  # - The initializer currently derives this from VERBENA_DELIVERY_METHOD and then calls configure.
  #
  # TODO (future improvements)
  # 1) 設定の固定化: 本番では `freeze!`/`frozen?` を導入して起動後の再設定を防止。開発では to_prepare で `reset!`→`configure`。
  # 2) 型/バリデーション強化: `parallel_concurrency >= 1`、`smtp_port` は正の整数、`enable_starttls_auto` の既定値の明示。
  # 3) Rails 設定フォールバック: `rescue nil` ではなく `dig`/安全ナビゲーションで取得するよう統一。
  # 4) 述語の追加: `smtp?`/`test?`/`file?` を提供して分岐を簡潔に。
  # 5) テスト補助: `with_overrides(**opts) { ... }` で一時上書き→ensure で復元するユーティリティ。
  # 6) 構成検証API: 不備時に例外/メッセージを返す `validate!`/`errors` を用意し、初期化子で利用可能に。
  class Settings
    class << self
      # Internal config holder
      class Config
        attr_accessor :delivery_method

        # SMTP
        attr_accessor :smtp_address, :smtp_port, :smtp_domain,
                :smtp_user_name, :smtp_password, :smtp_authentication,
                :smtp_enable_starttls_auto

        # Envelope-from override (optional)
        attr_accessor :envelope_from_override

        # File delivery
        attr_accessor :file_delivery_dir

        # API pagination
        attr_accessor :api_pagination_default_limit, :api_pagination_limit_cap, :api_pagination_default_offset

        # API response limits
        attr_accessor :api_responses_default_limit, :api_responses_limit_cap

        # General limits
        attr_accessor :eml_max_bytes

        # Cleanup TTL (days)
        attr_accessor :cleanup_ttl_days

        # Delivery retry/lock related
        attr_accessor :delivery_max_retries
        attr_accessor :delivery_lock_ttl_seconds, :delivery_lock_max_seconds

        # Delivery lock TTLs (seconds)
        attr_accessor :delivery_lock_ttl_seconds, :delivery_lock_max_seconds

        def initialize
          @delivery_method = nil
        end
      end

      # Access the singleton config object
      def config
        @config ||= Config.new
      end

      # Public readers
      def delivery_method
        raw = config.delivery_method
        return default_delivery_method if raw.nil?
        normalize_delivery_method(raw)
      end

      # API pagination readers
      def api_pagination_default_limit
        integer_cast(config.api_pagination_default_limit, 50)
      end

      def api_pagination_limit_cap
        integer_cast(config.api_pagination_limit_cap, 1000)
      end

      def api_pagination_default_offset
        integer_cast(config.api_pagination_default_offset, 0)
      end

      # API responses include limits
      def api_responses_default_limit
        integer_cast(config.api_responses_default_limit, 50)
      end

      def api_responses_limit_cap
        integer_cast(config.api_responses_limit_cap, 100)
      end

      # Mail delivery configs for helpers
      def smtp_delivery_config
        {
          address: config.smtp_address,
          port: (config.smtp_port || 0).to_i,
          domain: config.smtp_domain,
          user_name: config.smtp_user_name,
          password: config.smtp_password,
          authentication: config.smtp_authentication,
          enable_starttls_auto: boolean_cast(config.smtp_enable_starttls_auto, true),
          return_response: true,
        }
      end

      def file_delivery_dir
        config.file_delivery_dir.presence || Rails.root.join('tmp', 'mails').to_s
      end

      def file_delivery_config
        { location: file_delivery_dir }
      end

      # Envelope-from override accessor
      # Returns a non-empty string when configured, otherwise nil
      def envelope_from_override
        val = config.envelope_from_override.to_s.strip
        val.present? ? val : nil
      end

      # General readers
      def eml_max_bytes
        integer_cast(config.eml_max_bytes, 10 * 1024 * 1024) # default 10 MiB
      end

      # Cleanup TTL days (default 30)
      def cleanup_ttl_days
        days = integer_cast(config.cleanup_ttl_days, 30)
        days <= 0 ? 30 : days
      end

      # Delivery retry attempts (default 5)
      def delivery_max_retries
        n = integer_cast(config.delivery_max_retries, 5)
        n <= 0 ? 5 : n
      end

      # Delivery lock TTL (base seconds)
      def delivery_lock_ttl_seconds
        integer_cast(config.delivery_lock_ttl_seconds, 300)
      end

      # Delivery lock maximum seconds (cap)
      def delivery_lock_max_seconds
        integer_cast(config.delivery_lock_max_seconds, 3600)
      end

      # Configure settings at boot time.
      # Supports both hash style and block style similar to Rails.config.
      # Examples:
      #   Verbena::Settings.configure(delivery_method: :test)
      #   Verbena::Settings.configure do |c|
      #     c.delivery_method = :file
      #   end
      # Note: Normalization is applied in readers; no config-time normalization.
      def configure(options = nil)
        apply_hash(options) if options.is_a?(Hash)
        if block_given?
          yield config
        end
        self
      end

      # Useful for tests to clear any configured values
      def reset!
        @config = Config.new
      end

      private

      def default_delivery_method
        Rails.env.production? ? :smtp : :test
      end

      def normalize_delivery_method(value)
        v = value.is_a?(Symbol) ? value : value.to_s.strip.downcase.to_sym
        return v if %i[smtp test file].include?(v)
        default_delivery_method
      end

      # Apply flat hash of settings to the internal Config.
      #
      # Inputs
      # - hash: a flat Hash whose keys are strings or symbols matching Config attribute names
      #         (e.g., :smtp_address, 'parallel_concurrency', :api_pagination_limit_cap).
      #
      # Behavior
      # - Only assigns keys for which the Config object actually exposes a writer method
      #   (checked via respond_to? on "key="). This acts as an implicit allowlist and keeps
      #   unknown keys safely ignored without raising.
      # - Special case: delivery_method is normalized to one of :smtp, :test, :file.
      # - Keys are expected to be flat (no nested structures). This keeps the code simple
      #   and readable; both symbol and string keys are supported.
      # - Type conversion (integer/boolean) is intentionally performed by the public reader
      #   methods (e.g., api_pagination_default_limit, smtp_delivery_config), so writers store
      #   raw values and readers normalize them consistently.
      #
      # Security/maintenance considerations
      # - Because assignment is guarded by respond_to?("key="), adding a new attr_accessor to
      #   Config automatically makes it configurable via hash. If a future attribute should NOT
      #   be configurable this way, either:
      #     1) make the writer private, or
      #     2) switch back to a small explicit allowlist for that attribute.
      # - Unknown/unexpected keys are ignored.
      def apply_hash(hash)
        return unless hash.is_a?(Hash)

        hash.each do |raw_key, value|
          key = raw_key.is_a?(Symbol) ? raw_key : raw_key.to_s
          # Normalize to symbol form for comparisons, but check writer on config
          sym = key.to_sym

          # Special normalization
          if sym == :delivery_method
            config.delivery_method = normalize_delivery_method(value)
            next
          end

          writer = "#{key}="
          # Only assign when Config actually exposes the writer (acts as implicit allowlist)
          if config.respond_to?(writer)
            config.public_send(writer, value)
          end
        end
      end

      # Rails config fallbacks
      def boolean_cast(value, default = nil)
        return default if value.nil?
        ActiveModel::Type::Boolean.new.cast(value)
      end

      def integer_cast(value, default = nil)
        return default if value.nil?
        value.to_i
      end
    end
  end
end
