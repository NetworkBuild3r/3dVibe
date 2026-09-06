module API
  module V1
    class CoversController < ApplicationController
      skip_before_action :authenticate!, only: :writeback
      before_action :authenticate_writeback!, only: :writeback

      # Internal write-back for the Rendering worker.
      # POST /api/v1/covers/writeback
      # { model_id, status: "ready"|"failed", cover_url?, cover_placeholder?, asset_id?, cache_key? }
      def writeback
        model = CoverWriteback.apply!(writeback_params)
        render json: { model: VibeModel.card_payloads([model.reload], viewer: current_user).first }
      end

      private

      def writeback_params
        params.permit(:model_id, :id, :status, :cover_url, :cover_placeholder, :asset_id, :cache_key)
      end

      def authenticate_writeback!
        return if cover_authorized?

        authenticate!
      end
    end
  end
end
