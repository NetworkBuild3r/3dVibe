module API
  module V1
    class CoversController < ApplicationController
      skip_before_action :authenticate!, only: %i[show writeback]
      before_action :authenticate_writeback!, only: :writeback

      # Generated cover bytes. Filename is "{model_id}.webp" or
      # "{model_id}.lqip.webp" under VIBE_COVER_ROOT.
      def show
        filename = params[:filename].to_s
        unless filename.match?(/\A[0-9]+(?:\.lqip)?\.webp\z/)
          return render json: { error: "not_found" }, status: :not_found
        end

        path = File.expand_path(File.join(CoverGenerator.cover_root, filename))
        root = File.expand_path(CoverGenerator.cover_root)
        unless path.start_with?(root + File::SEPARATOR) && File.file?(path)
          return render json: { error: "not_found" }, status: :not_found
        end

        send_file path, type: "image/webp", disposition: "inline"
      end

      # Internal write-back for the generate worker.
      # POST /api/v1/covers/writeback
      # { model_id, status: "ready"|"failed", cover_url?, cover_lqip_url?, cover_placeholder?, asset_id?, cache_key? }
      def writeback
        model = CoverWriteback.apply!(writeback_params)
        render json: { model: VibeModel.card_payloads([model.reload], viewer: current_user).first }
      end

      private

      def writeback_params
        params.permit(:model_id, :id, :status, :cover_url, :cover_lqip_url, :cover_placeholder, :asset_id, :cache_key)
      end

      def authenticate_writeback!
        return if cover_authorized?

        authenticate!
      end
    end
  end
end
