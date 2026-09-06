require "base64"
require "digest"
require "json"
require "net/http"
require "securerandom"
require "socket"
require "stringio"
require "uri"

# SDCP-shaped LAN adapter (CBD / Elegoo Smart Device Control Protocol v3 JSON).
#
# The browser never talks to a printer. This class is the only process that
# opens sockets. Live I/O uses:
#   - WebSocket control: ws://{host}:{port}/websocket  (JSON envelopes)
#   - HTTP upload:       POST http://{host}:{port}/uploadFile/upload
#
# CI and unit tests inject StubTransport (or printer.settings["stub"]=true in
# test). A live host that does not speak this handshake fails soft — we never
# fake succeeded. Device-specific Ack quirks and binary variants need a real
# motherboard (escalate to Athena/Brian).
module PrinterAdapters
  class Sdcp < Base
    CMD_STATUS = 0
    CMD_ATTRIBUTES = 1
    CMD_START_PRINT = 128
    CMD_PAUSE = 129
    CMD_STOP = 130
    CMD_CONTINUE = 131
    CMD_TERMINATE_TRANSFER = 255

    DEFAULT_WS_PATH = "/websocket"
    DEFAULT_UPLOAD_PATH = "/uploadFile/upload"
    UPLOAD_CHUNK = 1 * 1024 * 1024

    PRINT_CTRL_ACK = {
      0 => nil,
      1 => "SDCP printer is busy (Ack=1)",
      2 => "SDCP file not found on printer (Ack=2)",
      3 => "SDCP MD5 verification failed (Ack=3)",
      4 => "SDCP file read failed (Ack=4)",
      5 => "SDCP resolution mismatch (Ack=5)",
      6 => "SDCP unrecognized file format (Ack=6)",
      7 => "SDCP machine model mismatch (Ack=7)"
    }.freeze

    def initialize(printer, timeout:, transport: nil)
      super(printer, timeout: timeout)
      @transport = transport
    end

    def submit(absolute_path, job:)
      unless File.file?(absolute_path.to_s)
        raise Error, "sdcp adapter cannot read print file"
      end

      filename = File.basename(absolute_path)
      size = File.size(absolute_path)
      md5 = Digest::MD5.file(absolute_path).hexdigest
      uuid = SecureRandom.hex(16)

      session = transport
      session.connect!
      status = session.command(CMD_STATUS, {}, job: job)
      raise Error, ack_message(status, fallback: "SDCP status request failed") unless ack_ok?(status)

      upload = File.open(absolute_path, "rb") do |io|
        session.upload(filename: filename, io: io, size: size, md5: md5, uuid: uuid, job: job)
      end
      raise Error, upload_message(upload) unless upload_ok?(upload)

      start = session.command(
        CMD_START_PRINT,
        { "Filename" => filename, "StartLayer" => 0 },
        job: job
      )
      raise Error, ack_message(start, fallback: "SDCP start print failed") unless ack_ok?(start)

      {
        remote_ref: remote_ref_for(start, uuid, filename),
        progress: 15,
        message: start_message(filename),
        complete: session.stub?
      }
    ensure
      transport&.close
    end

    def poll(job)
      result = transport.command(CMD_STATUS, {}, job: job)
      {
        status: job.status,
        progress: job.progress,
        remote_ref: job.remote_ref,
        ack: ack_value(result),
        raw: result
      }
    ensure
      transport&.close
    end

    def cancel(job)
      transport.connect!
      transport.command(CMD_STOP, {}, job: job)
      true
    ensure
      transport&.close
    end

    def simulate_progress(job)
      return unless transport.stub?

      delay = ENV.fetch("VIBE_PRINT_MOCK_DELAY_MS", "0").to_f / 1000.0
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

    def complete_after_submit?
      transport.stub?
    end

    def transport
      @transport ||= default_transport
    end

    def self.envelope(cmd:, data: {}, request_id:, mainboard_id:, client_id:, from: 0, time: Time.now.to_i)
      {
        "Id" => client_id.to_s,
        "Data" => {
          "Cmd" => cmd,
          "Data" => data,
          "RequestID" => request_id.to_s,
          "MainboardID" => mainboard_id.to_s,
          "TimeStamp" => time,
          "From" => from
        },
        "Topic" => "sdcp/request/#{mainboard_id}"
      }
    end

    def self.upload_form_fields(filename:, md5:, uuid:, size:, offset: 0)
      {
        "S-File-MD5" => md5,
        "Check" => "1",
        "Offset" => offset.to_s,
        "Uuid" => uuid,
        "TotalSize" => size.to_s,
        "filename" => filename
      }
    end

    private

    def default_transport
      if printer.sdcp_stub?
        StubTransport.new(printer, timeout: timeout)
      else
        HttpSocketTransport.new(printer, timeout: timeout)
      end
    end

    def ack_ok?(response)
      ack_value(response).to_i.zero?
    end

    def ack_value(response)
      data = response.is_a?(Hash) ? (response["Data"] || response[:Data] || response) : {}
      inner = data.is_a?(Hash) ? (data["Data"] || data[:Data] || data) : {}
      inner["Ack"] || inner[:Ack] || data["Ack"] || response["Ack"] || 1
    end

    def ack_message(response, fallback:)
      PRINT_CTRL_ACK[ack_value(response).to_i] || "#{fallback} (Ack=#{ack_value(response)})"
    end

    def upload_ok?(response)
      return false unless response.is_a?(Hash)

      code = response["code"] || response[:code]
      return true if code.to_s == "000000" || code.to_s == "0"
      return true if response["Ack"].to_i.zero? && response.key?("Ack")

      false
    end

    def upload_message(response)
      return "SDCP upload failed" unless response.is_a?(Hash)

      "SDCP upload failed (code=#{response['code'] || response[:code] || 'unknown'})"
    end

    def remote_ref_for(start, uuid, filename)
      data = start.is_a?(Hash) ? start.dig("Data", "Data") : nil
      task = data.is_a?(Hash) ? (data["TaskId"] || data["task_id"]) : nil
      task.presence || "sdcp-#{uuid}-#{filename}"
    end

    def start_message(filename)
      if transport.stub?
        "SDCP stub accepted #{filename} on #{printer.host}"
      else
        "SDCP start print accepted for #{filename} on #{printer.host}:#{printer.endpoint_port}. " \
          "Job stays printing until the device reports completion."
      end
    end
  end
end
