module API
  module V1
    class CreatorsController < ApplicationController
      def index
        counts = VibeModel.group(:creator_id).count
        creators = Creator.ordered.to_a
        render json: {
          creators: creators.map { |creator| creator.as_api(model_count: counts[creator.id] || 0) }
        }
      end

      def show
        creator = find_creator
        scope = accessible_models.where(creator_id: creator.id).for_cards.recent
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
          creator: creator.as_api(model_count: creator.vibe_models.count),
          models: VibeModel.card_payloads(models, viewer: current_user),
          next_cursor: has_more ? models.last&.id : nil
        }
      end

      private

      def find_creator
        key = params[:id].to_s
        if key.match?(/\A\d+\z/)
          Creator.find_by(id: key) || Creator.find_by!(slug: key)
        else
          Creator.find_by!(slug: key)
        end
      end
    end
  end
end
