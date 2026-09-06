module API
  module V1
    class LibrariesController < ApplicationController
      def index
        libraries = accessible_libraries.includes(:scan_runs).order(:name)
        render json: { libraries: libraries.map { |library| serialize(library) } }
      end

      def show
        library = accessible_libraries.find(params[:id])
        render json: { library: serialize(library, detail: true) }
      end

      def create
        unless current_user.owner_anywhere?
          render json: { error: "forbidden" }, status: :forbidden
          return
        end

        library = Library.create!(library_params)
        Membership.create!(user: current_user, library: library, role: Membership::OWNER)
        render json: { library: serialize(library) }, status: :created
      end

      def scan
        library = accessible_libraries.find(params[:id])
        return if require_owner!(library)

        prefix = params[:path_prefix].presence
        library.scan_runs.create!(
          status: ScanRun::QUEUED,
          trigger: ScanRun::TRIGGER_API,
          path_prefix: prefix,
          triggered_by: current_user,
          phase: ScanRun::PHASE_WALK
        )
        IncrementalScanJob.perform_later(library.id, prefix, current_user.id, ScanRun::TRIGGER_API)
        render json: { queued: true, library_id: library.id, library: serialize(library.reload, detail: true) },
               status: :accepted
      end

      private

      def library_params
        params.require(:library).permit(:name, :root_path, :notes)
      end

      def serialize(library, detail: false)
        membership = current_user.memberships.find_by(library: library)
        owner = current_user.owner_of?(library)
        payload = {
          id: library.id,
          name: library.name,
          root_path: library.root_path,
          notes: library.notes,
          model_count: library.vibe_models.count,
          shared: true,
          role: membership&.role || Membership::VIEWER,
          can_upload: current_user.can_upload?(library),
          can_print: current_user.can_print?(library),
          can_manage_printers: owner,
          can_scan: owner
        }
        payload[:scan] = serialize_scan(library) if owner
        return payload unless detail

        extra = {}
        extra[:scan_settings] = ScanSettings.as_api if owner
        extra[:cursors] = library.scan_cursors.order(:path_prefix).map { |cursor| serialize_cursor(cursor) } if owner
        payload.merge(extra)
      end

      def serialize_scan(library)
        run = library.latest_scan_run
        return { status: "idle" } unless run

        run.as_api
      end

      def serialize_cursor(cursor)
        {
          path_prefix: cursor.path_prefix,
          last_mtime: cursor.last_mtime,
          last_byte_size: cursor.last_byte_size,
          last_inode: cursor.last_inode,
          last_nlink: cursor.last_nlink,
          last_dir_mtime: cursor.last_dir_mtime,
          last_file_count: cursor.last_file_count,
          last_scanned_at: cursor.last_scanned_at,
          last_deep_scanned_at: cursor.last_deep_scanned_at,
          resume_relative_path: cursor.resume_relative_path
        }
      end
    end
  end
end
