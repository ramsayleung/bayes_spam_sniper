class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  before_action :authenticate

  private

  def authenticate
    authenticate_or_request_with_http_basic do |username, password|
      expected_username = ENV.fetch("ADMIN_USERNAME") { Rails.application.credentials.dig(:admin, :username) }
      expected_password = ENV.fetch("ADMIN_PASSWORD") { Rails.application.credentials.dig(:admin, :password) }

      if expected_username.blank? || expected_password.blank?
        Rails.logger.error "Authentication credentials not configured. Please set ADMIN_USERNAME and ADMIN_PASSWORD."
        false
      else
        ActiveSupport::SecurityUtils.secure_compare(username, expected_username) &
          ActiveSupport::SecurityUtils.secure_compare(password, expected_password)
      end
    end
  end
end
