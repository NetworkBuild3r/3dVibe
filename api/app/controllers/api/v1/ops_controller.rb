module API
  module V1
    class OpsController < ApplicationController
      def show
        # GET /ops?library_id= and GET /libraries/:id/ops share this action.
        library_id = params[:library_id].presence || params[:id]
        if library_id.present?
          library = accessible_libraries.find(library_id)
          return if require_curator!(library)

          render json: { ops: OpsSnapshot.new(library).as_api }
          return
        end

        libraries = curator_libraries
        if libraries.empty?
          render json: { error: "forbidden" }, status: :forbidden
          return
        end

        meili = OpsSnapshot.meili_health
        render json: {
          meili: meili,
          libraries: libraries.map { |library| OpsSnapshot.new(library, meili: meili).as_api }
        }
      end

      private

      def curator_libraries
        accessible_libraries
          .joins(:memberships)
          .where(memberships: { user_id: current_user.id, role: Membership::UPLOAD_ROLES })
          .includes(:scan_runs, :scan_cursors)
          .distinct
          .order(:name)
      end
    end
  end
end
