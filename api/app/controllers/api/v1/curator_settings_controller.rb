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
        update_secret!(:xai_api_key)
      end

      def destroy_xai_api_key
        destroy_secret!(:xai_api_key)
      end

      def update_openai_api_key
        update_secret!(:openai_api_key)
      end

      def destroy_openai_api_key
        destroy_secret!(:openai_api_key)
      end

      def update_anthropic_api_key
        update_secret!(:anthropic_api_key)
      end

      def destroy_anthropic_api_key
        destroy_secret!(:anthropic_api_key)
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

      def update_secret!(attribute)
        key = secret_param(attribute)
        if key.blank?
          render json: { error: "invalid", details: ["#{attribute} is required"] }, status: :unprocessable_entity
          return
        end

        setting = CuratorSetting.instance!
        setting.update!(attribute => key)
        render json: { curator_setting: setting.as_api }
      end

      def destroy_secret!(attribute)
        setting = CuratorSetting.instance
        setting&.update!(attribute => nil)
        render json: { curator_setting: CuratorRuntime.as_api }
      end

      def secret_param(attribute)
        nested = params[:curator_setting]
        raw = params[attribute]
        raw = nested[attribute] if raw.blank? && nested.respond_to?(:[])
        raw.to_s.strip
      end
    end
  end
end
