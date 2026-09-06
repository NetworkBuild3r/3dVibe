module API
  module V1
    class GeometryController < ApplicationController
      skip_before_action :authenticate!, only: :writeback
      before_action :authenticate_writeback!, only: :writeback

      # Internal write-back for the Rendering worker.
      # POST /api/v1/geometry/writeback
      # { asset_id, geometry_digest }
      def writeback
        asset = GeometryWriteback.apply!(writeback_params)
        render json: { asset: serialize(asset) }
      end

      private

      def writeback_params
        params.permit(:asset_id, :id, :geometry_digest)
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

      def authenticate_writeback!
        return if geometry_authorized?

        authenticate!
        return if performed?

        asset = Asset.find_by(id: params[:asset_id].presence || params[:id])
        library = asset&.vibe_model&.library
        return if library && current_user.can_curate?(library)

        render json: { error: "forbidden" }, status: :forbidden
      end
    end
  end
end
