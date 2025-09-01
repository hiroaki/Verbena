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
    config.load_defaults 7.0

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
    # OSS: Default to UTC for app and DB
    config.time_zone = "UTC"
    config.active_record.default_timezone = :utc

    # Disable colorized logging when JSON log format is requested via ENV.
    # This keeps JSON logs clean of ANSI escape sequences across all environments.
    if ENV['VERBENA_LOG_FORMAT'].to_s.strip.downcase == 'json'
      config.colorize_logging = false
      # Optionally reduce noisy verbose query logs in JSON mode (uncomment if desired):
      # config.active_record.verbose_query_logs = false
    end

    # Don't generate system test files.
    config.generators.system_tests = nil

    # verbena 固有の設定
    # config/verbena.yml に値を記述します。
    config.verbena = config_for(:verbena)
  end
end
