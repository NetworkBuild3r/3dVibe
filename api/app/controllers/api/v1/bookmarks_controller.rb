module API
  module V1
    class BookmarksController < ApplicationController
      def create
        folder = current_user.bookmark_folders.find(params[:bookmark_folder_id])
        model = accessible_models.find(params.require(:model_id))
        bookmark = current_user.bookmarks.find_or_create_by!(bookmark_folder: folder, vibe_model: model)
        render json: { bookmark: bookmark.as_api, model: VibeModel.card_payloads([model], viewer: current_user).first },
               status: bookmark.previously_new_record? ? :created : :ok
      end

      def destroy
        folder = current_user.bookmark_folders.find(params[:bookmark_folder_id])
        bookmark = folder.bookmarks.find_by!(vibe_model_id: params[:id])
        model = bookmark.vibe_model
        bookmark.destroy!
        render json: { model: VibeModel.card_payloads([model], viewer: current_user).first }
      end
    end
  end
end
