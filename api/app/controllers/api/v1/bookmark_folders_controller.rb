module API
  module V1
    class BookmarkFoldersController < ApplicationController
      def index
        folders = current_user.bookmark_folders.ordered.includes(:bookmarks)
        render json: { bookmark_folders: folders.map { |folder| folder.as_api } }
      end

      def show
        folder = current_user.bookmark_folders.includes(vibe_models: VibeModel::CARD_INCLUDES).find(params[:id])
        payload = folder.as_api(include_models: false).merge(
          models: VibeModel.card_payloads(folder.vibe_models, viewer: current_user)
        )
        render json: { bookmark_folder: payload }
      end

      def create
        folder = current_user.bookmark_folders.create!(folder_params.merge(position: next_position))
        render json: { bookmark_folder: folder.as_api }, status: :created
      end

      def update
        folder = current_user.bookmark_folders.find(params[:id])
        folder.update!(folder_params)
        render json: { bookmark_folder: folder.as_api }
      end

      def destroy
        folder = current_user.bookmark_folders.find(params[:id])
        folder.destroy!
        head :no_content
      end

      private

      def folder_params
        source = params[:bookmark_folder].is_a?(ActionController::Parameters) ? params.require(:bookmark_folder) : params
        source.permit(:name, :position).tap do |permitted|
          permitted[:name] = permitted[:name].to_s.strip if permitted[:name]
        end
      end

      def next_position
        current_user.bookmark_folders.maximum(:position).to_i + 1
      end
    end
  end
end
