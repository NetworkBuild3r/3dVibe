module API
  module V1
    class SessionsController < ApplicationController
      skip_before_action :authenticate!, only: :create

      def create
        user = User.find_by(email: params.require(:email).to_s.strip.downcase)
        if user&.authenticate(params.require(:password))
          token = user.access_tokens.create!(expires_at: 14.days.from_now)
          render json: { token: token.token, user: user_payload(user) }, status: :created
        else
          render json: { error: "invalid_credentials" }, status: :unauthorized
        end
      end

      def show
        render json: { user: user_payload(current_user) }
      end

      def destroy
        @current_token.destroy!
        head :no_content
      end

      private

      def user_payload(user)
        {
          id: user.id,
          email: user.email,
          display_name: user.display_name,
          libraries: user.memberships.includes(:library).map do |membership|
            {
              id: membership.library_id,
              name: membership.library.name,
              role: membership.role
            }
          end
        }
      end
    end
  end
end
