module API
  module V1
    class VibeModelsController < ApplicationController
      def index
        scope = accessible_models.includes(:tags, :library, :uploaded_by, :assets).recent
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
          models: models.map(&:as_card),
          next_cursor: has_more ? models.last&.id : nil
        }
      end

      def show
        model = accessible_models.includes(:tags, :uploaded_by, assets: %i[archive_members uploaded_by]).find(params[:id])
        render json: { model: detail_payload(model) }
      end

      private

      def detail_payload(model)
        model.as_card.merge(
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
              archive_member_count: asset.archive_members.size,
              archive_truncated: asset.archive_truncated,
              archive_support: asset.archive_support,
              uploaded_by: asset.uploaded_by && { id: asset.uploaded_by.id, display_name: asset.uploaded_by.display_name }
            }
          end
        )
      end
    end
  end
end
