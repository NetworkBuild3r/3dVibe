module PrinterAdapters
  class Sdcp
    # Live LAN transport. WebSocket for control JSON; HTTP multipart for file
    # chunks. Timeouts and connection errors become PrinterAdapters::Error so
    # PrinterBridge can fail_soft! — they must not become 500s.
    class HttpSocketTransport
      attr_reader :printer, :timeout

      def initialize(printer, timeout:)
        @printer = printer
        @timeout = [timeout.to_i, 1].max
        @session = nil
      end

      def stub?
        false
      end

      def connect!
        @session = Session.new(
          host: printer.endpoint_host,
          port: printer.endpoint_port,
          path: ws_path,
          token: printer.sdcp_token,
          timeout: open_timeout
        )
        @session.connect!
      rescue Timeout, ::Timeout::Error
        raise Timeout, "SDCP websocket timed out (#{printer.endpoint_host}:#{printer.endpoint_port})"
      rescue Error
        raise
      rescue SystemCallError, SocketError, IOError => error
        raise Error, "SDCP host unreachable (#{printer.endpoint_host}:#{printer.endpoint_port}): #{error.class}"
      end

      def command(cmd, data, job:)
        connect! unless @session&.open?
        request_id = SecureRandom.hex(8)
        payload = Sdcp.envelope(
          cmd: cmd,
          data: data,
          request_id: request_id,
          mainboard_id: printer.sdcp_mainboard_id,
          client_id: printer.sdcp_client_id
        )
        @session.send_json(payload)
        @session.read_json
      rescue Timeout, ::Timeout::Error
        raise Timeout, "SDCP command #{cmd} timed out (job=#{job&.id})"
      rescue Error
        raise
      rescue SystemCallError, SocketError, IOError, JSON::ParserError => error
        raise Error, "SDCP command #{cmd} failed: #{error.class}: #{error.message}"
      end

      def upload(filename:, io:, size:, md5:, uuid:, job:)
        offset = 0
        last = { "code" => "000000" }
        while offset < size
          chunk = io.read([Sdcp::UPLOAD_CHUNK, size - offset].min)
          raise Error, "SDCP upload read short at offset #{offset}" if chunk.nil?

          last = post_chunk(
            filename: filename,
            chunk: chunk,
            size: size,
            md5: md5,
            uuid: uuid,
            offset: offset
          )
          offset += chunk.bytesize
        end
        last
      rescue Timeout, ::Timeout::Error
        raise Timeout, "SDCP upload timed out (job=#{job&.id})"
      rescue Error
        raise
      rescue SystemCallError, SocketError, IOError => error
        raise Error, "SDCP upload failed: #{error.class}: #{error.message}"
      end

      def close
        @session&.close
        @session = nil
      end

      private

      def ws_path
        from_settings = printer.settings.is_a?(Hash) ? printer.settings["ws_path"].presence : nil
        from_settings || ENV.fetch("VIBE_SDCP_WS_PATH", Sdcp::DEFAULT_WS_PATH)
      end

      def upload_path
        from_settings = printer.settings.is_a?(Hash) ? printer.settings["upload_path"].presence : nil
        from_settings || ENV.fetch("VIBE_SDCP_UPLOAD_PATH", Sdcp::DEFAULT_UPLOAD_PATH)
      end

      def open_timeout
        ENV.fetch("VIBE_SDCP_OPEN_TIMEOUT", [timeout, 3].min.to_s).to_i
      end

      def post_chunk(filename:, chunk:, size:, md5:, uuid:, offset:)
        uri = URI::HTTP.build(host: printer.endpoint_host, port: printer.endpoint_port, path: upload_path)
        boundary = "----VibeSdcp#{SecureRandom.hex(12)}"
        fields = Sdcp.upload_form_fields(filename: filename, md5: md5, uuid: uuid, size: size, offset: offset)
        body = +""
        fields.each do |name, value|
          next if name == "filename"

          body << "--#{boundary}\r\n"
          body << "Content-Disposition: form-data; name=\"#{name}\"\r\n\r\n"
          body << "#{value}\r\n"
        end
        body << "--#{boundary}\r\n"
        body << "Content-Disposition: form-data; name=\"File\"; filename=\"#{filename}\"\r\n"
        body << "Content-Type: application/octet-stream\r\n\r\n"
        body << chunk.b
        body << "\r\n--#{boundary}--\r\n"

        request = Net::HTTP::Post.new(uri.request_uri)
        request["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
        request["Accept"] = "application/json"
        request["Authorization"] = "Bearer #{printer.sdcp_token}" if printer.sdcp_token
        request.body = body

        http = Net::HTTP.new(uri.host, uri.port)
        http.open_timeout = open_timeout
        http.read_timeout = timeout
        http.write_timeout = timeout if http.respond_to?(:write_timeout=)
        response = http.request(request)
        unless response.code.to_i.between?(200, 299)
          raise Error, "SDCP upload HTTP #{response.code}: #{response.body.to_s.truncate(240)}"
        end

        parse_upload_body(response.body)
      end

      def parse_upload_body(body)
        return { "code" => "000000" } if body.to_s.strip.empty?

        parsed = JSON.parse(body)
        parsed.is_a?(Hash) ? parsed : { "code" => "000000" }
      rescue JSON::ParserError
        raise Error, "SDCP upload returned non-JSON: #{body.to_s.truncate(120)}"
      end

      # Minimal RFC 6455 client. Control frames only; no extensions.
      class Session
        def initialize(host:, port:, path:, token:, timeout:)
        @host = host
        @port = port
        @path = path.start_with?("/") ? path : "/#{path}"
        @token = token
        @timeout = [timeout.to_i, 1].max
        @socket = nil
      end

      def connect!
        @socket = Socket.tcp(@host, @port, connect_timeout: @timeout)
        key = Base64.strict_encode64(SecureRandom.random_bytes(16))
        request = +"GET #{@path} HTTP/1.1\r\n"
        request << "Host: #{@host}:#{@port}\r\n"
        request << "Upgrade: websocket\r\n"
        request << "Connection: Upgrade\r\n"
        request << "Sec-WebSocket-Key: #{key}\r\n"
        request << "Sec-WebSocket-Version: 13\r\n"
        request << "Authorization: Bearer #{@token}\r\n" if @token.present?
        request << "\r\n"
        @socket.write(request)
        headers = read_http_headers
        first = headers.lines.first.to_s.strip
        unless first.match?(%r{\AHTTP/1\.[01] 101\b})
          raise Error, "SDCP websocket handshake failed: #{first.presence || 'empty response'}"
        end

        true
      end

      def open?
        @socket && !@socket.closed?
      end

      def send_json(payload)
        write_frame(payload.to_json)
      end

      def read_json
        JSON.parse(read_text)
      end

      def close
        return unless open?

        write_frame("", opcode: 0x8)
        @socket.close
      rescue StandardError
        @socket&.close
      ensure
        @socket = nil
      end

      private

      def read_http_headers
        buffer = +""
        while (chunk = read_some)
          buffer << chunk
          break if buffer.include?("\r\n\r\n")
        end
        buffer
      end

      def write_frame(payload, opcode: 0x1)
        data = payload.to_s.b
        header = [0x80 | opcode].pack("C")
        length = data.bytesize
        mask_bit = 0x80
        header << if length <= 125
          [mask_bit | length].pack("C")
        elsif length <= 0xFFFF
          [mask_bit | 126, length].pack("Cn")
        else
          [mask_bit | 127, length].pack("CQ>")
        end
        mask = SecureRandom.random_bytes(4)
        masked = data.bytes.map.with_index { |byte, index| byte ^ mask.getbyte(index % 4) }.pack("C*")
        @socket.write(header + mask + masked)
      end

      def read_text
        loop do
          byte0 = read_exact(1).getbyte(0)
          byte1 = read_exact(1).getbyte(0)
          opcode = byte0 & 0x0f
          masked = (byte1 & 0x80) != 0
          length = byte1 & 0x7f
          length = read_exact(2).unpack1("n") if length == 126
          length = read_exact(8).unpack1("Q>") if length == 127
          mask = masked ? read_exact(4) : nil
          payload = read_exact(length)
          if mask
            payload = payload.bytes.map.with_index { |byte, index| byte ^ mask.getbyte(index % 4) }.pack("C*")
          end
          case opcode
          when 0x1, 0x2
            return payload.force_encoding("UTF-8")
          when 0x8
            raise Error, "SDCP websocket closed by printer"
          when 0x9
            write_frame(payload, opcode: 0xA)
          when 0xA
            next
          else
            raise Error, "SDCP websocket unexpected opcode #{opcode}"
          end
        end
      end

      def read_exact(length)
        return +"" if length <= 0

        buffer = +""
        while buffer.bytesize < length
          chunk = read_some(length - buffer.bytesize)
          raise Error, "SDCP websocket closed" if chunk.nil? || chunk.empty?

          buffer << chunk
        end
        buffer
      end

      def read_some(maxlen = 4096)
        raise Error, "SDCP websocket is not open" unless open?

        readable, = IO.select([@socket], nil, nil, @timeout)
        raise Timeout, "SDCP websocket read timed out" unless readable

        @socket.read_nonblock(maxlen)
      rescue IO::WaitReadable
        retry
      rescue EOFError
        raise Error, "SDCP websocket closed"
      end
    end
    end
  end
end
