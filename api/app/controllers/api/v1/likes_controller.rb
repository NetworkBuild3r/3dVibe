module API
  module V1
    class LikesController < ApplicationController
      def index
        models = VibeModel.joins(:likes)
                          .where(likes: { user_id: current_user.id })
                          .for_cards
                          .order("likes.created_at DESC")
        render json: { models: VibeModel.card_payloads(models, viewer: current_user) }
      end
    end
  end
end
