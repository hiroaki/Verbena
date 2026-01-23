class Admin::BaseController < ApplicationController
  before_action :authenticate_admin!

  private

  def authenticate_admin!
    authenticate_or_request_with_http_basic("Administration") do |username, password|
      valid = username == Verbena::Settings.admin_username &&
              password == Verbena::Settings.admin_password &&
              Verbena::Settings.admin_username.present? &&
              Verbena::Settings.admin_password.present?
      Rails.logger.debug { "Basic authentication: #{valid}" }
      valid
    end
  end
end
