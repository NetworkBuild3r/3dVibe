# frozen_string_literal: true

require "base64"
require "net/http"
require "uri"
require_relative "config"

module VibeCurator
  # Load at most one ready-cover image for the live chat message.
  # Prefer LQIP, else cover_url. Missing / over-budget / failed fetch → nil
  # (text-only fallback). Stub never calls this. No mesh bytes.
  module Vision
    COVER_FILENAME = /\A[0-9]+(?:\.lqip)?\.webp\z/
    COVER_PATH = %r{\A/covers/[0-9]+(?:\.lqip)?\.webp\z}
    HTTP_URL = /\Ahttps?:\/\//i

    Attachment = Struct.new(:bytes, :mime, :model_id, :folder_name, :source, keyword_init: true) do
      def data_url
        "data:#{mime};base64,#{Base64.strict_encode64(bytes)}"
      end

      def base64
        Base64.strict_encode64(bytes)
      end

      def pointer
        {
          "model_id" => model_id,
          "folder_name" => folder_name,
          "source" => source
        }
      end
    end

    module_function

    def attach(catalog, env: ENV, fetch: nil)
      pick = pick_cover(catalog)
      return unless pick

      bytes = load_bytes(pick[:url], env: env, fetch: fetch)
      return unless bytes
      return if bytes.bytesize > Config.vision_max_bytes(env: env)

      mime = detect_mime(bytes)
      return unless mime

      width, height = dimensions(bytes)
      max_px = Config.vision_max_px(env: env)
      return if width && height && (width > max_px || height > max_px)

      Attachment.new(
        bytes: bytes,
        mime: mime,
        model_id: pick[:model_id],
        folder_name: pick[:folder_name],
        source: pick[:source]
      )
    rescue StandardError
      nil
    end

    # First ready cover among catalog models (already ranked by the caller).
    def pick_cover(catalog)
      models = catalog.is_a?(Hash) ? Array(catalog["models"]) : Array(catalog)
      models.each do |model|
        data = model.is_a?(Hash) ? model.transform_keys(&:to_s) : {}
        next unless data["cover_status"].to_s == "ready"

        lqip = Config.present(data["cover_lqip_url"])
        cover = Config.present(data["cover_url"])
        url = lqip || cover
        next unless url

        return {
          url: url,
          source: lqip ? "cover_lqip_url" : "cover_url",
          model_id: data["id"],
          folder_name: data["folder_name"]
        }
      end
      nil
    end

    def load_bytes(url, env: ENV, fetch: nil)
      text = url.to_s.strip
      return if text.empty?
      return decode_data_url(text) if text.start_with?("data:image/")

      if COVER_PATH.match?(text)
        local = read_cover_root(text, env)
        return local if local

        base = Config.present(env["VIBE_COVER_BASE_URL"])
        return unless base

        text = join_base(base, text)
      end

      return unless HTTP_URL.match?(text)

      fetcher = fetch || method(:http_get)
      fetcher.call(text, env)
    end

    def read_cover_root(url, env)
      root = Config.present(env["VIBE_COVER_ROOT"])
      return unless root

      name = File.basename(url)
      return unless COVER_FILENAME.match?(name)

      base = File.expand_path(root)
      path = File.expand_path(File.join(base, name))
      return unless path.start_with?(base + File::SEPARATOR)
      return unless File.file?(path)

      File.binread(path)
    end

    def join_base(base, path)
      URI.join(base.end_with?("/") ? base : "#{base}/", path.delete_prefix("/")).to_s
    end

    def http_get(url, env)
      uri = URI.parse(url)
      return unless uri.is_a?(URI::HTTP)

      timeout = Config.vision_timeout(env: env)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = timeout
      http.read_timeout = timeout
      request = Net::HTTP::Get.new(uri.request_uri)
      request["Accept"] = "image/*,*/*"
      response = http.request(request)
      code = response.code.to_i
      return unless code.between?(200, 299)

      body = response.body.to_s
      body.empty? ? nil : body.b
    end

    def decode_data_url(text)
      match = text.match(/\Adata:(image\/[a-zA-Z0-9.+-]+);base64,(.+)\z/m)
      return unless match

      Base64.decode64(match[2]).b
    rescue ArgumentError
      nil
    end

    def detect_mime(bytes)
      head = bytes.byteslice(0, 16).to_s
      return "image/png" if head.start_with?("\x89PNG\r\n\x1a\n".b)
      return "image/webp" if head.start_with?("RIFF".b) && bytes.byteslice(8, 4) == "WEBP"
      return "image/jpeg" if head.start_with?("\xFF\xD8".b)
      return "image/gif" if head.start_with?("GIF87a") || head.start_with?("GIF89a")

      nil
    end

    def dimensions(bytes)
      mime = detect_mime(bytes)
      case mime
      when "image/png" then png_size(bytes)
      when "image/webp" then webp_size(bytes)
      when "image/jpeg" then jpeg_size(bytes)
      when "image/gif" then gif_size(bytes)
      end
    end

    def png_size(bytes)
      return unless bytes.bytesize >= 24

      [bytes.byteslice(16, 4).unpack1("N"), bytes.byteslice(20, 4).unpack1("N")]
    end

    def gif_size(bytes)
      return unless bytes.bytesize >= 10

      [bytes.byteslice(6, 2).unpack1("v"), bytes.byteslice(8, 2).unpack1("v")]
    end

    def webp_size(bytes)
      return unless bytes.bytesize >= 30
      return unless bytes.byteslice(0, 4) == "RIFF" && bytes.byteslice(8, 4) == "WEBP"

      fourcc = bytes.byteslice(12, 4)
      case fourcc
      when "VP8X"
        return unless bytes.bytesize >= 30

        w = read24(bytes, 24) + 1
        h = read24(bytes, 27) + 1
        [w, h]
      when "VP8 "
        return unless bytes.bytesize >= 30

        # lossy payload starts at 20; frame tag is 3 bytes then 3-byte sync + 14-bit sizes
        return unless bytes.byteslice(23, 3) == "\x9D\x01\x2A".b

        packed = bytes.byteslice(26, 4).unpack1("V")
        [(packed & 0x3FFF), ((packed >> 16) & 0x3FFF)]
      when "VP8L"
        return unless bytes.bytesize >= 25
        return unless bytes.getbyte(20) == 0x2F

        bits = bytes.byteslice(21, 4).unpack1("V")
        [((bits & 0x3FFF) + 1), (((bits >> 14) & 0x3FFF) + 1)]
      end
    end

    def jpeg_size(bytes)
      offset = 2
      while offset + 9 < bytes.bytesize
        return unless bytes.getbyte(offset) == 0xFF

        marker = bytes.getbyte(offset + 1)
        offset += 2
        next if marker == 0xD8 || marker == 0xD9 || (marker >= 0xD0 && marker <= 0xD7)

        length = bytes.byteslice(offset, 2).unpack1("n")
        return if length.nil? || length < 2

        if [0xC0, 0xC1, 0xC2, 0xC3].include?(marker) && offset + 7 <= bytes.bytesize
          return [bytes.byteslice(offset + 5, 2).unpack1("n"), bytes.byteslice(offset + 3, 2).unpack1("n")]
        end

        offset += length
      end
      nil
    end

    def read24(bytes, offset)
      b0, b1, b2 = bytes.byteslice(offset, 3).bytes
      b0 | (b1 << 8) | (b2 << 16)
    end
  end
end
