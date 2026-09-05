module API
  module V1
    class InvitesController < ApplicationController
      skip_before_action :authenticate!, only: :redeem

      def index
        invites = Invite.where(library_id: owner_library_ids).order(created_at: :desc)
        render json: { invites: invites.map { |invite| serialize(invite) } }
      end

      def create
        library = accessible_libraries.find(params.require(:library_id))
        return if require_owner!(library)

        invite = library.invites.create!(
          invited_by: current_user,
          email: params.require(:email).to_s.strip.downcase,
          role: params.fetch(:role, Membership::FRIEND),
          expires_at: 14.days.from_now
        )
        render json: { invite: serialize(invite) }, status: :created
      end

      def redeem
        invite = Invite.find_by!(token: params[:token])
        unless invite.pending?
          render json: { error: "invite_inactive" }, status: :conflict
          return
        end

        user = User.find_by(email: invite.email)
        if user.nil?
          user = User.create!(
            email: invite.email,
            display_name: invite.email.split("@").first,
            password: params.require(:password),
            password_confirmation: params.require(:password)
          )
        elsif params[:password].present? && !user.authenticate(params[:password])
          render json: { error: "invalid_credentials" }, status: :unauthorized
          return
        end

        invite.redeem!(user)
        token = user.access_tokens.create!(expires_at: 14.days.from_now)
        render json: { token: token.token, user: { id: user.id, email: user.email, display_name: user.display_name } }
      end

      private

      def owner_library_ids
        current_user.memberships.where(role: Membership::OWNER).select(:library_id)
      end

      def serialize(invite)
        {
          id: invite.id,
          library_id: invite.library_id,
          email: invite.email,
          role: invite.role,
          token: invite.token,
          pending: invite.pending?,
          expires_at: invite.expires_at,
          redeemed_at: invite.redeemed_at
        }
      end
    end
  end
end
