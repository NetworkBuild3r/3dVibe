module API
  module V1
    class ArchiveMembersController < ApplicationController
      def index
        model = accessible_models.find(params[:model_id])
        members = ArchiveMember.joins(:asset).where(assets: { vibe_model_id: model.id }).order(:internal_path)

        render json: {
          model_id: model.id,
          members: members.map { |member| serialize(member) }
        }
      end

      def preview
        member = ArchiveMember.joins(asset: :vibe_model)
                              .where(vibe_models: { library_id: accessible_libraries.select(:id) })
                              .find(params[:id])

        unless member.previewable? && %w[zip 3mf].include?(member.asset.kind)
          render json: { error: "preview_unavailable" }, status: :unprocessable_entity
          return
        end

        ArchiveIndexer.new(member.asset).stream_member(member.internal_path) do |entry, io|
          send_data io.read,
                    filename: File.basename(entry.name),
                    type: "application/octet-stream",
                    disposition: "inline"
        end
      end

      private

      def serialize(member)
        {
          id: member.id,
          asset_id: member.asset_id,
          internal_path: member.internal_path,
          directory: member.directory,
          compressed_size: member.compressed_size,
          uncompressed_size: member.uncompressed_size,
          previewable: member.previewable?,
          extension: member.extension
        }
      end
    end
  end
end
