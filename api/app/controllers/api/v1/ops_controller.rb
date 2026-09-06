module API
  module V1
    class OpsController < ApplicationController
      def show
        if params[:library_id].present?
          library = accessible_libraries.find(params[:library_id])
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
