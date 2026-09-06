module API
  module V1
    class GeometryController < ApplicationController
      skip_before_action :authenticate!, only: :writeback
      before_action :authenticate_writeback!, only: :writeback

      # Internal write-back for the Rendering worker.
      # POST /api/v1/geometry/writeback
      # { asset_id | archive_member_id, geometry_digest }
      def writeback
        record = GeometryWriteback.apply!(writeback_params)
        if record.is_a?(ArchiveMember)
          render json: { archive_member: serialize_member(record) }
        else
          render json: { asset: serialize(record) }
        end
      end

      private

      def writeback_params
        params.permit(:asset_id, :id, :archive_member_id, :geometry_digest)
      end

      def serialize(asset)
        {
          id: asset.id,
          filename: asset.filename,
          relative_path: asset.relative_path,
          kind: asset.kind,
          byte_size: asset.byte_size,
          content_digest: asset.content_digest,
          geometry_digest: asset.geometry_digest,
          model_id: asset.vibe_model_id
        }
      end

      def serialize_member(member)
        asset = member.asset
        {
          id: member.id,
          archive_member_id: member.id,
          asset_id: asset.id,
          parent_asset_id: asset.id,
          parent_filename: asset.filename,
          member_path: member.internal_path,
          archive_path: member.archive_path,
          filename: member.basename,
          geometry_digest: member.geometry_digest,
          model_id: asset.vibe_model_id
        }
      end

      def authenticate_writeback!
        return if geometry_authorized?

        authenticate!
        return if performed?

        library = writeback_library
        return if library && current_user.can_curate?(library)

        render json: { error: "forbidden" }, status: :forbidden
      end

      def writeback_library
        if params[:archive_member_id].present?
          ArchiveMember.find_by(id: params[:archive_member_id])&.asset&.vibe_model&.library
        else
          Asset.find_by(id: params[:asset_id].presence || params[:id])&.vibe_model&.library
        end
      end
    end
  end
end
