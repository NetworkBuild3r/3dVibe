module API
  module V1
    class CuratorSettingsController < ApplicationController
      before_action :require_site_owner!

      def show
        render json: { curator_setting: CuratorRuntime.as_api }
      end

      def update
        setting = CuratorSetting.instance!
        setting.update!(setting_params)
        render json: { curator_setting: setting.as_api }
      end

      def update_xai_api_key
        key = params[:xai_api_key].to_s.strip
        if key.blank?
          render json: { error: "invalid", details: ["xai_api_key is required"] }, status: :unprocessable_entity
          return
        end

        setting = CuratorSetting.instance!
        setting.update!(xai_api_key: key)
        render json: { curator_setting: setting.as_api }
      end

      def destroy_xai_api_key
        setting = CuratorSetting.instance
        setting&.update!(xai_api_key: nil)
        render json: { curator_setting: CuratorRuntime.as_api }
      end

      private

      def require_site_owner!
        return if current_user.owner_anywhere?

        render json: { error: "forbidden" }, status: :forbidden
      end

      def setting_params
        source = params[:curator_setting].respond_to?(:permit) ? params.require(:curator_setting) : params
        permitted = source.permit(:provider, :ollama_url, :ollama_model)
        permitted[:ollama_url] = permitted[:ollama_url].presence if permitted.key?(:ollama_url)
        permitted[:ollama_model] = permitted[:ollama_model].presence if permitted.key?(:ollama_model)
        permitted
      end
    end
  end
end
