module API
  module V1
    class SearchController < ApplicationController
      def index
        query = params[:q].to_s
        scope = accessible_models.includes(:tags, :library)
        models = ModelSearch.new(scope, query: query).results.recent.limit(50)

        render json: {
          query: query,
          engine: ENV["MEILISEARCH_URL"].present? ? "meilisearch" : "postgres",
          models: models.map do |model|
            {
              id: model.id,
              title: model.title,
              folder_name: model.folder_name,
              synopsis: model.synopsis,
              tags: model.tags.map(&:name),
              library_id: model.library_id
            }
          end
        }
      end
    end
  end
end
