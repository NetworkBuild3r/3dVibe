module API
  module V1
    class SearchController < ApplicationController
      def index
        query = params[:q].to_s
        scope = accessible_models.includes(:tags, :library, :uploaded_by)
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
              library_id: model.library_id,
              library_name: model.library.name,
              uploaded_by: model.uploaded_by && { id: model.uploaded_by.id, display_name: model.uploaded_by.display_name }
            }
          end
        }
      end
    end
  end
end
