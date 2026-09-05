module API
  module V1
    class LibrariesController < ApplicationController
      def index
        render json: { libraries: accessible_libraries.order(:name).map { |library| serialize(library) } }
      end

      def show
        library = accessible_libraries.find(params[:id])
        render json: { library: serialize(library, detail: true) }
      end

      def create
        library = Library.create!(library_params)
        Membership.create!(user: current_user, library: library, role: Membership::OWNER)
        render json: { library: serialize(library) }, status: :created
      end

      def scan
        library = accessible_libraries.find(params[:id])
        return if require_owner!(library)

        IncrementalScanJob.perform_later(library.id)
        render json: { queued: true, library_id: library.id }, status: :accepted
      end

      private

      def library_params
        params.require(:library).permit(:name, :root_path, :notes)
      end

      def serialize(library, detail: false)
        payload = {
          id: library.id,
          name: library.name,
          root_path: library.root_path,
          notes: library.notes,
          model_count: library.vibe_models.count
        }
        return payload unless detail

        payload.merge(
          cursors: library.scan_cursors.order(:path_prefix).map do |cursor|
            {
              path_prefix: cursor.path_prefix,
              last_mtime: cursor.last_mtime,
              last_byte_size: cursor.last_byte_size,
              last_scanned_at: cursor.last_scanned_at
            }
          end
        )
      end
    end
  end
end
