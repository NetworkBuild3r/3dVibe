require "fileutils"

# libvips thumbnail + webp encode, clamped to max_px / max_bytes.
# Uses shrink-on-load (Vips::Image.thumbnail) so huge sources are never decoded whole.
class CoverImage
  MIN_QUALITY = 35
  MIN_EDGE = 32

  def self.encode(source, dest, budget)
    require "vips"

    max_px = budget.fetch("max_px").to_i
    max_bytes = budget.fetch("max_bytes").to_i
    raise CoverGenerator::PermanentError, "invalid cover budget" if max_px <= 0 || max_bytes <= 0

    FileUtils.mkdir_p(File.dirname(dest))
    image = Vips::Image.thumbnail(source.to_s, max_px, height: max_px, size: :down)
    image = image.flatten(background: [255, 255, 255]) if image.has_alpha?

    quality = 82
    tmp = "#{dest}.tmp-#{Process.pid}-#{SecureRandom.hex(4)}"
    begin
      write_webp(image, tmp, quality)
      while File.size(tmp) > max_bytes && quality > MIN_QUALITY
        quality = [quality - 12, MIN_QUALITY].max
        write_webp(image, tmp, quality)
      end

      shrinks = 0
      while File.size(tmp) > max_bytes && [image.width, image.height].max > MIN_EDGE && shrinks < 8
        image = image.resize(0.75)
        write_webp(image, tmp, quality)
        shrinks += 1
      end

      raise CoverGenerator::PermanentError, "cover exceeds max_bytes after clamp" if File.size(tmp) > max_bytes

      FileUtils.mv(tmp, dest)
    ensure
      FileUtils.rm_f(tmp)
    end
  rescue CoverGenerator::TransientError, CoverGenerator::PermanentError
    raise
  rescue Vips::Error => e
    raise CoverGenerator::PermanentError, "image encode failed: #{e.message}"
  rescue *CoverGenerator::TRANSIENT_ERRNO => e
    raise CoverGenerator::TransientError, e.message
  end

  def self.write_webp(image, path, quality)
    image.webpsave(path, Q: quality, strip: true)
  end
end
