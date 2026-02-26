# Use the production environment settings as a base
# and override only the staging environment-specific settings.
# production 環境の設定をベースにし、 staging 環境固有の設定のみオーバーライドするようにします。
require_relative "production"

Rails.application.configure do
  config.log_level = :debug

  # TODO: production が決まり次第調整します。少なくともメール環境は変更する必要があります。
  # config.action_mailer.delivery_method = :smtp
  # config.action_mailer.smtp_settings = {
  #   address: ENV['SMTP_ADDRESS'],
  #   port: ENV['SMTP_PORT'],
  # }
end
