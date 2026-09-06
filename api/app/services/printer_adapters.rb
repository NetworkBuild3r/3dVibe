# Printer protocol adapters. The browser never talks to a printer; only this
# process (API or Sidekiq worker) opens a LAN session.
#
# To add a real protocol (SDCP, Moonraker, OctoPrint, …):
#   1. Subclass PrinterAdapters::Base and implement #submit, #poll, #cancel.
#   2. Register it in PrinterAdapters.for.
#   3. Add the protocol key to Printer::PROTOCOL_TYPES.
#   4. Keep timeouts inside the adapter (or rely on PrinterBridge) so a hung
#      printer cannot 502 the web UI.
module PrinterAdapters
  class Error < StandardError; end
  class Timeout < Error; end
  class NotConfigured < Error; end

  def self.for(printer, timeout: ENV.fetch("VIBE_PRINT_TIMEOUT", "15").to_i)
    case printer.protocol_type
    when Printer::MOCK then Mock.new(printer, timeout: timeout)
    when Printer::SDCP then Sdcp.new(printer, timeout: timeout)
    else
      raise Error, "unknown printer protocol #{printer.protocol_type}"
    end
  end

  class Base
    attr_reader :printer, :timeout

    def initialize(printer, timeout:)
      @printer = printer
      @timeout = timeout
    end

    # Open the jailed file and hand it to the printer. Return a hash with
    # :remote_ref and optional :progress / :message.
    def submit(_absolute_path, job:)
      raise NotConfigured, "#{self.class.name} must implement #submit"
    end

    def poll(job)
      { status: job.status, progress: job.progress, remote_ref: job.remote_ref }
    end

    def cancel(_job)
      true
    end

    def simulate_progress(_job)
      nil
    end
  end

  # Always-on stub for CI and local compose. Reads the jailed file (to prove the
  # path jail) and walks queued → sending → printing → succeeded. No sockets.
  class Mock < Base
    def submit(absolute_path, job:)
      unless File.file?(absolute_path.to_s)
        raise Error, "mock adapter cannot read print file"
      end

      File.open(absolute_path, "rb") { |io| io.read(64) }
      {
        remote_ref: "mock-#{job.id}-#{File.basename(absolute_path)}",
        progress: 15,
        message: "Mock printer accepted #{File.basename(absolute_path)}"
      }
    end

    def simulate_progress(job)
      delay = mock_delay
      [
        [PrintDispatch::SENDING, 25],
        [PrintDispatch::PRINTING, 55],
        [PrintDispatch::PRINTING, 85]
      ].each do |status, progress|
        return if job.reload.terminal?

        sleep(delay) if delay.positive?
        job.update!(status: status, progress: progress)
      end
    end

    private

    def mock_delay
      ENV.fetch("VIBE_PRINT_MOCK_DELAY_MS", "0").to_f / 1000.0
    end
  end

  # Placeholder for a future LAN SDCP (or SDCP-like) client. The interface is
  # stable; this class must not open sockets in this slice.
  class Sdcp < Base
    def submit(_absolute_path, job:)
      raise NotConfigured, sdcp_message(job)
    end

    def poll(_job)
      raise NotConfigured, "SDCP poll is not implemented. Set protocol_type=mock for local/CI."
    end

    def cancel(_job)
      raise NotConfigured, "SDCP cancel is not implemented."
    end

    private

    def sdcp_message(job)
      host = printer.host
      "SDCP adapter is not implemented yet (host=#{host}, job=#{job.id}). " \
        "Use protocol_type=mock, or add a PrinterAdapters::Sdcp client that talks to the printer from the worker."
    end
  end
end
