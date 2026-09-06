module API
  module V1
    class SearchController < ApplicationController
      def index
        result = ModelSearch.new(
          accessible_models,
          query: params[:q],
          filters: {
            tags: search_tags,
            library_id: params[:library_id],
            uploaded_by_id: params[:uploaded_by_id],
            has_preview: params[:has_preview]
          },
          offset: params.fetch(:offset, 0),
          limit: params.fetch(:limit, 18)
        ).call

        render json: {
          query: result.query,
          engine: result.engine,
          fallback: result.fallback,
          offset: result.offset,
          limit: result.limit,
          estimated_total: result.estimated_total,
          next_offset: result.next_offset,
          facets: result.facets,
          models: VibeModel.card_payloads(result.models, viewer: current_user)
        }
      end

      private

      def search_tags
        values = []
        values.concat(Array(params[:tags]))
        values << params[:tag]
        values.flatten.compact
      end
    end
  end
end
