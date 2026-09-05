module API
  module V1
    class VibeModelsController < ApplicationController
      def index
        scope = accessible_models.includes(:tags, :library).recent
        scope = scope.where(library_id: params[:library_id]) if params[:library_id].present?
        limit = [[params.fetch(:limit, 24).to_i, 1].max, 60].min

        if params[:cursor].present?
          cursor_model = scope.find_by(id: params[:cursor])
          if cursor_model
            scope = scope.where(
              "(vibe_models.updated_at < ?) OR (vibe_models.updated_at = ? AND vibe_models.id < ?)",
              cursor_model.updated_at, cursor_model.updated_at, cursor_model.id
            )
          end
        end

        models = scope.limit(limit + 1).to_a
        has_more = models.length > limit
        models = models.first(limit)

        render json: {
          models: models.map { |model| card_payload(model) },
          next_cursor: has_more ? models.last&.id : nil
        }
      end

      def show
        model = accessible_models.includes(:tags, assets: :archive_members).find(params[:id])
        render json: { model: detail_payload(model) }
      end

      private

      def card_payload(model)
        {
          id: model.id,
          title: model.title,
          folder_name: model.folder_name,
          synopsis: model.synopsis,
          asset_count: model.asset_count,
          byte_size: model.byte_size,
          library_id: model.library_id,
          library_name: model.library.name,
          tags: model.tags.map(&:name),
          updated_at: model.updated_at
        }
      end

      def detail_payload(model)
        card_payload(model).merge(
          folder_mtime: model.folder_mtime,
          assets: model.assets.order(:relative_path).map do |asset|
            {
              id: asset.id,
              filename: asset.filename,
              relative_path: asset.relative_path,
              kind: asset.kind,
              byte_size: asset.byte_size,
              content_digest: asset.content_digest,
              archive: asset.archive?,
              mesh: asset.mesh?,
              archive_member_count: asset.archive_members.size
            }
          end
        )
      end
    end
  end
end
