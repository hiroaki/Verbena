class Admin::BaseController < ApplicationController
  before_action :authenticate_admin!

  private

  def authenticate_admin!
    authenticate_or_request_with_http_basic("Administration") do |username, password|
      expected_username = Verbena::Settings.admin_username.to_s
      expected_password = Verbena::Settings.admin_password.to_s

      username_valid = expected_username.present? &&
                       username.to_s.bytesize == expected_username.bytesize &&
                       ActiveSupport::SecurityUtils.secure_compare(username.to_s, expected_username)

      password_valid = expected_password.present? &&
                       password.to_s.bytesize == expected_password.bytesize &&
                       ActiveSupport::SecurityUtils.secure_compare(password.to_s, expected_password)

      username_valid && password_valid
    end
  end
end
