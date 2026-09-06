module API
  module V1
    class PrintJobsController < ApplicationController
      def index
        jobs = PrintDispatch.includes(:printer, :vibe_model, :asset, :requested_by, :library).recent.limit(100)
        jobs = jobs.where(status: params[:status]) if params[:status].present?
        render json: { print_jobs: jobs.map { |job| serialize(job) } }
      end

      def show
        job = PrintDispatch.find(params[:id])
        render json: { print_job: serialize(job) }
      end

      def create
        model = accessible_models.find(params.require(:model_id))
        library = model.library
        return if require_print!(library)

        asset = find_asset!(model)
        printer = find_printer!(library)

        job = PrintDispatch.new(
          library: library,
          printer: printer,
          vibe_model: model,
          asset: asset,
          requested_by: current_user,
          status: PrintDispatch::QUEUED,
          progress: 0,
          protocol_type: printer.protocol_type,
          filename: asset.filename,
          printer_hint: printer.name,
          note: "Queued for #{printer.name} via #{printer.protocol_type} adapter."
        )
        PrintFileResolver.new(job).absolute_path
        job.save!
        DispatchPrintJob.perform_later(job.id)

        render json: { print_job: serialize(job) }, status: :accepted
      end

      def cancel
        job = PrintDispatch.find(params[:id])
        unless can_cancel?(job)
          render json: { error: "forbidden" }, status: :forbidden
          return
        end

        unless job.cancel!("Cancelled by #{current_user.display_name}")
          render json: { error: "not_cancellable", print_job: serialize(job) }, status: :conflict
          return
        end

        render json: { print_job: serialize(job.reload) }
      end

      private

      def find_asset!(model)
        asset_id = params[:asset_id].presence
        asset = asset_id ? model.assets.find_by(id: asset_id) : model.assets.find_by(kind: Asset::MESH_KINDS)
        raise ArgumentError, "printable file is required" if asset.blank?

        asset
      end

      def find_printer!(library)
        printer_id = params[:printer_id].presence
        raise ArgumentError, "printer_id is required" if printer_id.blank?

        printer = library.printers.find(printer_id)
        raise ArgumentError, "printer is disabled" unless printer.enabled?

        printer
      end

      def can_cancel?(job)
        job.requested_by_id == current_user.id || current_user.owner_of?(job.library || job.vibe_model&.library)
      end

      def serialize(job)
        {
          id: job.id,
          library_id: job.library_id,
          printer_id: job.printer_id,
          printer_name: job.printer&.name || job.printer_hint,
          protocol_type: job.protocol_type || job.printer&.protocol_type,
          model_id: job.vibe_model_id,
          model_title: job.vibe_model&.title,
          asset_id: job.asset_id,
          filename: job.filename || job.asset&.filename,
          status: job.status,
          progress: job.progress,
          printer_hint: job.printer_hint,
          note: job.note,
          error_message: job.error_message,
          remote_ref: job.remote_ref,
          requested_by: job.requested_by && {
            id: job.requested_by.id,
            display_name: job.requested_by.display_name
          },
          started_at: job.started_at,
          finished_at: job.finished_at,
          created_at: job.created_at,
          updated_at: job.updated_at
        }
      end
    end
  end
end
