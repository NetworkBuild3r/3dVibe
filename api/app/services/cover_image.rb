require "fileutils"

# libvips thumbnail + webp encode, clamped to max_px / max_bytes.
# Uses shrink-on-load (Vips::Image.thumbnail) so huge sources are never decoded whole.
# Optional LQIP writes a second tiny blurred webp from the already-resized thumbnail
# (no second NFS decode, no archive slurp).
class CoverImage
  MIN_QUALITY = 35
  MIN_EDGE = 32
  LQIP_MIN_QUALITY = 20
  LQIP_MIN_EDGE = 8

  def self.encode(source, dest, budget, lqip_dest: nil, lqip_budget: nil)
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

    write_lqip(image, lqip_dest, lqip_budget, cover_path: dest) if lqip_dest.present?
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

  # Best-effort tiny derivative. Cover generate already succeeded; LQIP failure
  # must not flip the model to failed. Prefer shrink-on-load of the already
  # written cover webp (budgeted, never the original NFS source).
  def self.write_lqip(image, dest, budget, cover_path: nil)
    require "vips"

    max_px, max_bytes = lqip_limits(budget, image)
    return if max_px <= 0 || max_bytes <= 0 || dest.blank?

    FileUtils.mkdir_p(File.dirname(dest))
    thumb = lqip_source_image(image, cover_path, max_px)
    thumb = thumb.flatten(background: [255, 255, 255]) if thumb.has_alpha?
    thumb = apply_lqip_blur(thumb)

    quality = 45
    tmp = "#{dest}.tmp-#{Process.pid}-#{SecureRandom.hex(4)}"
    begin
      write_webp(thumb, tmp, quality)
      while File.size(tmp) > max_bytes && quality > LQIP_MIN_QUALITY
        quality = [quality - 8, LQIP_MIN_QUALITY].max
        write_webp(thumb, tmp, quality)
      end

      shrinks = 0
      while File.size(tmp) > max_bytes && [thumb.width, thumb.height].max > LQIP_MIN_EDGE && shrinks < 6
        thumb = thumb.resize(0.75)
        write_webp(thumb, tmp, quality)
        shrinks += 1
      end

      if File.size(tmp) > max_bytes
        Rails.logger.warn("[CoverImage] lqip exceeds max_bytes after clamp dest=#{dest}")
        return
      end

      FileUtils.mv(tmp, dest)
    ensure
      FileUtils.rm_f(tmp)
    end
  rescue CoverGenerator::TransientError, CoverGenerator::PermanentError
    raise
  rescue Vips::Error => e
    Rails.logger.warn("[CoverImage] lqip encode failed: #{e.message}")
  rescue *CoverGenerator::TRANSIENT_ERRNO => e
    Rails.logger.warn("[CoverImage] lqip skipped: #{e.message}")
  end

  def self.lqip_source_image(image, cover_path, max_px)
    if cover_path && File.file?(cover_path)
      return Vips::Image.thumbnail(cover_path.to_s, max_px, height: max_px, size: :down)
    end

    shrink_in_memory(image, max_px)
  end

  def self.shrink_in_memory(image, max_px)
    edge = [image.width, image.height].max
    return image if edge <= max_px || max_px <= 0

    image.resize(max_px.to_f / edge)
  end

  def self.lqip_limits(budget, image)
    raw = budget.respond_to?(:to_h) ? budget.to_h.stringify_keys : {}
    max_px = raw["max_px"].to_i
    max_bytes = raw["max_bytes"].to_i
    max_px = CoverEnqueue::DEFAULT_LQIP_MAX_PX if max_px <= 0
    max_bytes = CoverEnqueue::DEFAULT_LQIP_MAX_BYTES if max_bytes <= 0
    edge = [image.width, image.height].max
    max_px = [max_px, edge].min if edge.positive?
    [max_px, max_bytes]
  end

  def self.apply_lqip_blur(image)
    return image unless image.respond_to?(:gaussblur)
    return image if [image.width, image.height].min < 16

    image.gaussblur(0.8)
  rescue Vips::Error
    image
  end
end
