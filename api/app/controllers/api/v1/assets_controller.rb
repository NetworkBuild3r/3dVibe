module API
  module V1
    class AssetsController < ApplicationController
      def show
        asset = find_asset
        render json: {
          asset: {
            id: asset.id,
            filename: asset.filename,
            relative_path: asset.relative_path,
            kind: asset.kind,
            byte_size: asset.byte_size,
            content_digest: asset.content_digest,
            geometry_digest: asset.geometry_digest,
            mesh: asset.mesh?,
            archive: asset.archive?
          }
        }
      end

      def content
        asset = find_asset
        path = asset.absolute_path
        raise ActiveRecord::RecordNotFound unless File.file?(path)

        send_file path, filename: asset.filename, disposition: "inline"
      end

      private

      def find_asset
        Asset.joins(vibe_model: :library)
             .where(libraries: { id: accessible_libraries.select(:id) })
             .find(params[:id])
      end
    end
  end
end
