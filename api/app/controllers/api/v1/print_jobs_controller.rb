module API
  module V1
    class PrintJobsController < ApplicationController
      def index
        jobs = PrintDispatch.where(requested_by: current_user).order(created_at: :desc).limit(50)
        render json: { print_jobs: jobs.map { |job| serialize(job) } }
      end

      def create
        model = accessible_models.find(params.require(:model_id))
        asset = model.assets.find_by(id: params[:asset_id])

        job = PrintDispatch.create!(
          vibe_model: model,
          asset: asset,
          requested_by: current_user,
          status: "unavailable",
          printer_hint: params[:printer_hint],
          note: "Printer bridge is a placeholder. No SDCP session is opened in this MVP."
        )

        render json: { print_job: serialize(job) }, status: :accepted
      end

      private

      def serialize(job)
        {
          id: job.id,
          model_id: job.vibe_model_id,
          asset_id: job.asset_id,
          status: job.status,
          printer_hint: job.printer_hint,
          note: job.note,
          created_at: job.created_at
        }
      end
    end
  end
end
