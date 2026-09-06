module API
  module V1
    class VibeModelsController < ApplicationController
      def index
        scope = ModelCatalogFilters.apply(
          accessible_models.for_cards.recent,
          library_id: params[:library_id],
          tags: gallery_tags,
          creator_slug: params[:creator_slug].presence || params[:creator],
          cover_status: params[:cover_status],
          has_cover: params[:has_cover]
        )
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
          models: VibeModel.card_payloads(models, viewer: current_user),
          next_cursor: has_more ? models.last&.id : nil
        }
      end

      def show
        model = accessible_models.includes(:tags, :uploaded_by, :creator, assets: %i[archive_members uploaded_by]).find(params[:id])
        render json: { model: detail_payload(model) }
      end

      def like
        model = accessible_models.find(params[:id])
        current_user.likes.find_or_create_by!(vibe_model: model)
        render json: { model: detail_payload(model.reload), liked: true }
      end

      def unlike
        model = accessible_models.find(params[:id])
        current_user.likes.where(vibe_model: model).delete_all
        render json: { model: detail_payload(model.reload), liked: false }
      end

      def merge
        library = accessible_libraries.find(params.require(:library_id))
        return if require_curator!(library)

        record = ModelComposer.new(library, performed_by: current_user).merge!(
          source_ids: params[:source_ids] || params[:model_ids],
          asset_ids: params[:asset_ids],
          target_id: params[:target_id],
          title: params[:title],
          folder_name: params[:folder_name]
        )
        target = accessible_models.includes(:tags, :uploaded_by, :creator, assets: %i[archive_members uploaded_by])
                                 .find(record.target_vibe_model_id)
        render json: { merge: record.as_api, model: detail_payload(target) }, status: :created
      end

      def split
        model = accessible_models.find(params[:id])
        return if require_curator!(model.library)

        record = ModelComposer.new(model.library, performed_by: current_user).split!(
          model,
          merge_id: params[:merge_id]
        )
        restored = restored_models(record)
        render json: {
          merge: record.as_api,
          models: VibeModel.card_payloads(restored, viewer: current_user)
        }
      end

      private

      def gallery_tags
        values = []
        values.concat(Array(params[:tags]))
        values << params[:tag]
        values.flatten.compact
      end

      def detail_payload(model)
        card = VibeModel.card_payloads([model], viewer: current_user).first
        card.merge(
          folder_mtime: model.folder_mtime,
          merges: model.model_merges.includes(:performed_by).recent.map(&:as_api),
          assets: model.assets.order(:relative_path).map do |asset|
            {
              id: asset.id,
              filename: asset.filename,
              relative_path: asset.relative_path,
              kind: asset.kind,
              byte_size: asset.byte_size,
              content_digest: asset.content_digest,
              geometry_digest: asset.geometry_digest,
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

      def restored_models(record)
        names = Array(record.result["restored"]).filter_map { |part| part["folder_name"] }
        record.library.vibe_models.where(folder_name: names).for_cards
      end
    end
  end
end
