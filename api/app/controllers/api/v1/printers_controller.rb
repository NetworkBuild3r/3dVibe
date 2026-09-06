module API
  module V1
    class PrintersController < ApplicationController
      def index
        printers = Printer.includes(:library).by_name
        printers = printers.enabled unless current_user.owner_anywhere?
        render json: { printers: printers.map { |printer| serialize(printer) } }
      end

      def show
        printer = Printer.find(params[:id])
        if !printer.enabled? && !current_user.owner_of?(printer.library)
          render json: { error: "not_found" }, status: :not_found
          return
        end

        render json: { printer: serialize(printer) }
      end

      def create
        library = accessible_libraries.find(params.require(:library_id))
        return if require_owner!(library)

        printer = library.printers.create!(printer_params)
        render json: { printer: serialize(printer) }, status: :created
      end

      def update
        printer = Printer.find(params[:id])
        return if require_owner!(printer.library)

        printer.update!(printer_params)
        render json: { printer: serialize(printer) }
      end

      def destroy
        printer = Printer.find(params[:id])
        return if require_owner!(printer.library)

        printer.destroy!
        head :no_content
      end

      private

      def printer_params
        permitted = params.permit(:name, :host, :protocol_type, :enabled, :notes, settings: {})
        if params[:printer].respond_to?(:permit)
          permitted = params.require(:printer).permit(:name, :host, :protocol_type, :enabled, :notes, settings: {})
        end
        permitted[:enabled] = ActiveModel::Type::Boolean.new.cast(permitted[:enabled]) if permitted.key?(:enabled)
        permitted
      end

      def serialize(printer)
        {
          id: printer.id,
          library_id: printer.library_id,
          library_name: printer.library.name,
          name: printer.name,
          host: printer.host,
          protocol_type: printer.protocol_type,
          enabled: printer.enabled,
          notes: printer.notes,
          settings: printer.settings,
          created_at: printer.created_at,
          updated_at: printer.updated_at
        }
      end
    end
  end
end
