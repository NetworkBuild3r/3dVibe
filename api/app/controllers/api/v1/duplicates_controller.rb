module API
  module V1
    class DuplicatesController < ApplicationController
      def index
        library = if params[:library_id].present?
          accessible_libraries.find(params[:library_id])
        else
          accessible_libraries.order(:id).first
        end
        raise ActiveRecord::RecordNotFound unless library

        render json: DuplicateFinder.new(library).call
      end
    end
  end
end
