class DispatchPrintJob < ApplicationJob
  queue_as :print

  discard_on ActiveRecord::RecordNotFound

  def perform(print_dispatch_id)
    job = PrintDispatch.find(print_dispatch_id)
    PrinterBridge.new(job).run!
  rescue StandardError => error
    PrintDispatch.find_by(id: print_dispatch_id)&.fail_soft!("#{error.class}: #{error.message}")
    Rails.logger.warn("[DispatchPrintJob] failed id=#{print_dispatch_id} #{error.class}: #{error.message}")
  end
end
