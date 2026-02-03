module Api
  module V1
    class ApplicationController < ActionController::API
      include ActionController::HttpAuthentication::Token::ControllerMethods

      before_action :authenticate_or_render_error

      attr_reader :current_token

      def render_unauthorized
        render_error('unauthorized', 'token invalid', :unauthorized)
      end

      protected
        def render_error(code, message, status)
          render json: { code: code.to_s, message: message.to_s }, status: status
        end

      private
        # Pagination helpers (defaults and caps)
        # Default: from Verbena::Settings (fallbacks: limit=50, offset=0, cap=1000)
        def pagination_limit
          raw = params[:limit].to_i
          default = Verbena::Settings.api_pagination_default_limit
          cap = Verbena::Settings.api_pagination_limit_cap
          return default if raw <= 0
          [raw, cap].min
        end

        def pagination_offset
          raw = params[:offset].to_i
          default = Verbena::Settings.api_pagination_default_offset
          return default if raw.negative?
          raw
        end

        def authenticate_or_render_error
          authenticated? || render_unauthorized
        end

        def authenticated?
          authenticate_with_http_token do |token, _options|
            @current_token = Token.authenticate(token)
          end
        end

      public
    end
  end
end
