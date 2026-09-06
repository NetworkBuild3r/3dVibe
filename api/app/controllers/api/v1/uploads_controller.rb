require "base64"

module API
  module V1
    class UploadsController < ApplicationController
      def create
        library = accessible_libraries.find(params.require(:library_id))
        return if require_upload!(library)

        jail = LibraryPathJail.new(library.root_path)
        folder = jail.normalize_folder(params.require(:folder_name))
        relative = jail.normalize_relative(params[:relative_path].presence || params.require(:filename))
        byte_size = params.require(:byte_size).to_i
        enforce_size!(byte_size)

        upload = library.library_uploads.create!(
          uploaded_by: current_user,
          folder_name: folder,
          relative_path: relative,
          filename: File.basename(relative),
          byte_size: byte_size,
          byte_offset: 0,
          status: LibraryUpload::PENDING
        )
        prepare_incoming!(upload)
        finalize!(upload) if byte_size.zero?

        render json: { upload: serialize(upload.reload) }, status: :created
      end

      def show
        upload = find_upload
        render json: { upload: serialize(upload) }
      end

      def update
        upload = find_upload
        unless upload.pending?
          render json: { error: "not_pending", offset: upload.byte_offset }, status: :conflict
          return
        end

        offset = request.headers["Upload-Offset"].presence&.to_i || params[:offset].to_i
        if offset != upload.byte_offset
          render json: { error: "offset_mismatch", offset: upload.byte_offset }, status: :conflict
          return
        end

        appended = append_chunk!(upload)
        if appended.negative?
          render json: { error: "chunk_exceeds_size" }, status: :unprocessable_entity
          return
        end

        finalize!(upload.reload) if upload.byte_offset == upload.byte_size
        render json: { upload: serialize(upload.reload) }
      end

      def complete
        upload = find_upload
        finalize!(upload)
        render json: { upload: serialize(upload.reload) }
      end

      def direct
        library = accessible_libraries.find(params.require(:library_id))
        return if require_upload!(library)

        file = params.require(:file)
        jail = LibraryPathJail.new(library.root_path)
        folder = jail.normalize_folder(params.require(:folder_name))
        relative = jail.normalize_relative(params[:relative_path].presence || file.original_filename)
        enforce_size!(file.size)

        dest = jail.join(folder, relative)
        FileUtils.mkdir_p(dest.dirname)
        FileUtils.cp(file_source(file), dest)

        upload = library.library_uploads.create!(
          uploaded_by: current_user,
          folder_name: folder,
          relative_path: relative,
          filename: File.basename(relative),
          byte_size: dest.size,
          byte_offset: dest.size,
          status: LibraryUpload::COMPLETED,
          completed_at: Time.current
        )
        IncrementalScanJob.perform_later(library.id, folder, current_user.id)
        render json: { upload: serialize(upload) }, status: :created
      end

      private

      def find_upload
        current_user.library_uploads.find(params[:id])
      end

      def max_upload_bytes
        ENV.fetch("VIBE_MAX_UPLOAD_BYTES", 5.gigabytes).to_i
      end

      def enforce_size!(size)
        raise ArgumentError, "upload exceeds VIBE_MAX_UPLOAD_BYTES" if size > max_upload_bytes
      end

      def prepare_incoming!(upload)
        FileUtils.mkdir_p(upload.incoming_path.dirname)
        FileUtils.touch(upload.incoming_path)
      end

      def append_chunk!(upload)
        chunk = read_chunk
        return 0 if chunk.bytesize.zero?

        if upload.byte_offset + chunk.bytesize > upload.byte_size
          -1
        else
          File.open(upload.incoming_path, "ab") { |io| io.write(chunk) }
          upload.update!(byte_offset: upload.byte_offset + chunk.bytesize)
          chunk.bytesize
        end
      end

      def read_chunk
        if params[:chunk].respond_to?(:read)
          params[:chunk].read
        elsif params[:chunk_b64].present?
          Base64.decode64(params[:chunk_b64].to_s)
        else
          request.body.rewind
          request.body.read
        end
      end

      def file_source(file)
        file.respond_to?(:tempfile) ? file.tempfile.path : file.path
      end

      def finalize!(upload)
        return if upload.completed?
        raise ArgumentError, "upload incomplete" unless upload.byte_offset == upload.byte_size

        dest = upload.destination_path
        FileUtils.mkdir_p(dest.dirname)
        if File.exist?(upload.incoming_path)
          FileUtils.mv(upload.incoming_path, dest)
        else
          FileUtils.touch(dest)
        end
        upload.update!(status: LibraryUpload::COMPLETED, completed_at: Time.current)
        IncrementalScanJob.perform_later(upload.library_id, upload.folder_name, upload.uploaded_by_id)
      end

      def serialize(upload)
        {
          id: upload.id,
          library_id: upload.library_id,
          folder_name: upload.folder_name,
          relative_path: upload.relative_path,
          filename: upload.filename,
          byte_size: upload.byte_size,
          byte_offset: upload.byte_offset,
          status: upload.status,
          completed_at: upload.completed_at
        }
      end
    end
  end
end
