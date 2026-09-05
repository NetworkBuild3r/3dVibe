module API
  module V1
    class SessionsController < ApplicationController
      skip_before_action :authenticate!, only: :create

      def create
        user = User.find_by(email: params.require(:email).to_s.strip.downcase)
        if user&.authenticate(params.require(:password))
          token = user.access_tokens.create!(expires_at: 14.days.from_now)
          render json: { token: token.token, user: user.api_payload }, status: :created
        else
          render json: { error: "invalid_credentials" }, status: :unauthorized
        end
      end

      def show
        render json: { user: current_user.api_payload }
      end

      def destroy
        @current_token.destroy!
        head :no_content
      end
    end
  end
end
