require "timeout"

# Orchestrates one print job: path-jail the library file, hand it to the
# protocol adapter, and persist status. Failures are recorded on the row so the
# web UI never sees a 502 from a hung printer.
class PrinterBridge
  def self.timeout_seconds
    ENV.fetch("VIBE_PRINT_TIMEOUT", "15").to_i
  end

  def initialize(job, adapter: nil)
    @job = job
    @adapter = adapter
  end

  def run!
    return if @job.terminal?

    unless @job.printer
      @job.fail_soft!("No printer selected")
      return
    end

    unless @job.printer.enabled?
      @job.fail_soft!("Printer is disabled")
      return
    end

    @job.mark_sending!
    path = PrintFileResolver.new(@job).absolute_path
    adapter = @adapter || PrinterAdapters.for(@job.printer, timeout: self.class.timeout_seconds)
    result = with_timeout { adapter.submit(path, job: @job) }
    return if @job.reload.terminal?

    @job.update!(
      remote_ref: result[:remote_ref],
      note: result[:message].presence || @job.note,
      status: PrintDispatch::PRINTING,
      progress: (result[:progress] || 25).to_i.clamp(0, 99)
    )
    adapter.simulate_progress(@job)
    return if @job.reload.terminal?

    if result[:complete] == false || !adapter.complete_after_submit?
      return
    end

    @job.mark_succeeded!(result[:message])
  rescue PrinterAdapters::Timeout, Timeout::Error => error
    @job.fail_soft!("Printer timed out: #{error.message}")
  rescue PrinterAdapters::Error, ArgumentError, Errno::ENOENT => error
    @job.fail_soft!(error.message)
  rescue StandardError => error
    @job.fail_soft!("#{error.class}: #{error.message}")
  end

  private

  def with_timeout(&block)
    seconds = self.class.timeout_seconds
    return yield if seconds <= 0

    ::Timeout.timeout(seconds, PrinterAdapters::Timeout, "adapter exceeded #{seconds}s") do
      block.call
    end
  end
end
