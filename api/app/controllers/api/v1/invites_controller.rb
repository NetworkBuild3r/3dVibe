module API
  module V1
    class InvitesController < ApplicationController
      skip_before_action :authenticate!, only: %i[preview redeem]

      def index
        invites = Invite.where(library_id: owner_library_ids).order(created_at: :desc)
        render json: { invites: invites.map { |invite| serialize(invite) } }
      end

      def create
        library = accessible_libraries.find(params.require(:library_id))
        return if require_owner!(library)

        invite = library.invites.create!(
          invited_by: current_user,
          email: params[:email],
          role: invite_role,
          expires_at: invite_expiry
        )
        render json: { invite: serialize(invite) }, status: :created
      end

      def preview
        invite = Invite.find_by!(token: params[:token])
        render json: { invite: public_serialize(invite) }
      end

      def redeem
        invite = Invite.find_by!(token: params[:token])
        unless invite.pending?
          render json: { error: "invite_inactive" }, status: :conflict
          return
        end

        email = (params[:email].presence || invite.email).to_s.strip.downcase
        if email.blank?
          render json: { error: "invalid", details: ["email is required"] }, status: :unprocessable_entity
          return
        end
        if invite.email.present? && invite.email != email
          render json: { error: "invite_email_mismatch" }, status: :unprocessable_entity
          return
        end

        user = User.find_by(email: email)
        if user.nil?
          user = User.create!(
            email: email,
            display_name: params[:display_name].presence || email.split("@").first,
            password: params.require(:password),
            password_confirmation: params.require(:password)
          )
        elsif params[:password].present? && !user.authenticate(params[:password])
          render json: { error: "invalid_credentials" }, status: :unauthorized
          return
        end

        invite.redeem!(user)
        token = user.access_tokens.create!(expires_at: 14.days.from_now)
        render json: { token: token.token, user: user.api_payload }
      end

      def revoke
        invite = Invite.where(library_id: owner_library_ids).find(params[:id])
        return if require_owner!(invite.library)

        invite.revoke! unless invite.revoked_at
        render json: { invite: serialize(invite.reload) }
      end

      private

      def owner_library_ids
        current_user.memberships.where(role: Membership::OWNER).select(:library_id)
      end

      def invite_role
        params.fetch(:role, Membership::CONTRIBUTOR)
      end

      def invite_expiry
        return if params.key?(:expires_at) && params[:expires_at].blank?
        return Time.zone.parse(params[:expires_at].to_s) if params[:expires_at].present?
        return if params.key?(:expires_in_days) && params[:expires_in_days].blank?

        days = params.fetch(:expires_in_days, 14).to_i
        days.positive? ? days.days.from_now : nil
      end

      def serialize(invite)
        public_serialize(invite).merge(
          token: invite.token,
          redeem_path: invite.redeem_path
        )
      end

      def public_serialize(invite)
        {
          id: invite.id,
          library_id: invite.library_id,
          library_name: invite.library.name,
          email: invite.email,
          role: invite.role,
          pending: invite.pending?,
          expires_at: invite.expires_at,
          redeemed_at: invite.redeemed_at,
          revoked_at: invite.revoked_at
        }
      end
    end
  end
end
