Rails.application.config.after_initialize do
  begin
    engine_mounted = Rails.application.routes.routes.any? do |r|
      r.app == MissionControl::Jobs::Engine
    end

    if engine_mounted && (Verbena::Settings.admin_username.blank? || Verbena::Settings.admin_password.blank?)
      Rails.logger.warn "[Verbena] Admin routes are mounted but VERBENA_ADMIN_USERNAME / VERBENA_ADMIN_PASSWORD are not configured. Admin interface will be inaccessible."
    end
  rescue => e
    Rails.logger.debug { "verbena_admin_check: #{e.class}: #{e.message}" }
  end
end
