module PrinterAdapters
  class Sdcp
    # In-process SDCP path for tests. Records the same command / upload shapes
    # the live transport would send. Never opens sockets.
    class StubTransport
      attr_reader :printer, :timeout, :commands, :uploads

      def initialize(printer, timeout:, script: nil)
        @printer = printer
        @timeout = timeout
        @script = script || {}
        @commands = []
        @uploads = []
      end

      def stub?
        true
      end

      def connect!
        fail_if(:connect)
        true
      end

      def command(cmd, data, job:)
        envelope = Sdcp.envelope(
          cmd: cmd,
          data: data,
          request_id: SecureRandom.hex(8),
          mainboard_id: printer.sdcp_mainboard_id,
          client_id: printer.sdcp_client_id
        )
        @commands << { cmd: cmd, data: data, job_id: job&.id, envelope: envelope }
        fail_if(:command, cmd)
        ack_response(cmd, extra: extra_for(cmd))
      end

      def upload(filename:, io:, size:, md5:, uuid:, job:)
        io.read(64) if io.respond_to?(:read)
        fields = Sdcp.upload_form_fields(filename: filename, md5: md5, uuid: uuid, size: size)
        @uploads << { filename: filename, size: size, md5: md5, uuid: uuid, job_id: job&.id, fields: fields }
        fail_if(:upload)
        { "code" => "000000", "filename" => filename }
      end

      def close
        @closed = true
      end

      def closed?
        @closed == true
      end

      private

      def fail_if(step, cmd = nil)
        action = @script[step]
        action = action[cmd] if action.is_a?(Hash) && cmd
        case action
        when :timeout
          raise Timeout, "SDCP #{step} timed out"
        when :busy
          raise Error, Sdcp::PRINT_CTRL_ACK[1]
        when String
          raise Error, action
        when Exception
          raise action
        end
      end

      def extra_for(cmd)
        extras = @script[:extras]
        extras.is_a?(Hash) ? extras[cmd] : nil
      end

      def ack_response(cmd, extra: nil)
        inner = { "Ack" => 0 }
        inner.merge!(extra) if extra.is_a?(Hash)
        {
          "Id" => printer.sdcp_client_id,
          "Data" => {
            "Cmd" => cmd,
            "Data" => inner,
            "RequestID" => SecureRandom.hex(8),
            "MainboardID" => printer.sdcp_mainboard_id,
            "TimeStamp" => Time.now.to_i
          },
          "Topic" => "sdcp/response/#{printer.sdcp_mainboard_id}"
        }
      end
    end
  end
end
