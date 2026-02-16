require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Verbena
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Don't generate system test files.
    config.generators.system_tests = nil

    # I18n base configuration
    config.i18n.available_locales = %i[en ja]
    config.i18n.default_locale = :en
    # Use English as a fallback when running in Japanese.
    config.i18n.fallbacks = { ja: [:ja, :en], en: [:en] }

    #----------
    # 追加設定
    #

    # Verbena 固有の設定
    # config/verbena.yml に値を記述します。
    config.verbena = config_for(:verbena)

    # Default to UTC for app and DB
    config.time_zone = "UTC"
    config.active_record.default_timezone = :utc

    # Disable colorized logging when JSON log format is requested via ENV.
    # This keeps JSON logs clean of ANSI escape sequences across all environments.
    if ENV['VERBENA_LOG_FORMAT'].to_s.strip.downcase == 'json'
      config.colorize_logging = false
      # Optionally reduce noisy verbose query logs in JSON mode (uncomment if desired):
      # config.active_record.verbose_query_logs = false
    end

    # Use our admin controller for mission_control-jobs authentication/authorization.
    # Implement `authenticate_admin!` in `Admin::BaseController`.
    MissionControl::Jobs.base_controller_class = "Admin::BaseController"
    # Disable engine-level basic auth since we handle it in Admin::BaseController
    MissionControl::Jobs.http_basic_auth_enabled = false
  end
end
