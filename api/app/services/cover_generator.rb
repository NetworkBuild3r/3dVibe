# Budgeted cover generate for GenerateCoverJob.
# Resolves jailed_path via LibraryPathJail (never escapes, never slurps archives),
# writes a webp under VIBE_COVER_ROOT, then CoverWriteback.apply!.
class CoverGenerator
  IMAGE_EXT = %w[png jpg jpeg webp gif].freeze
  PREVIEW_STEMS = %w[cover preview thumb hero].freeze
  TRANSIENT_ERRNO = [
    Errno::EACCES, Errno::EAGAIN, Errno::EBUSY, Errno::EHOSTUNREACH,
    Errno::EIO, Errno::ENETDOWN, Errno::ENOENT, Errno::ESTALE
  ].freeze

  class TransientError < StandardError; end
  class PermanentError < StandardError; end

  def self.call(payload)
    new(payload).call
  end

  def self.cache_key_for(payload)
    data = stringify(payload)
    "#{data['asset_id']}:#{data['mtime'].to_i}:#{data['content_hash']}"
  end

  def self.cover_root
    ENV.fetch("VIBE_COVER_ROOT", Rails.root.join("tmp/covers").to_s)
  end

  def self.cover_url_for(model_id)
    "/covers/#{model_id}.webp"
  end

  def self.stringify(payload)
    data = payload.respond_to?(:to_unsafe_h) ? payload.to_unsafe_h : payload
    (data.presence || {}).to_h.stringify_keys
  end

  def initialize(payload)
    @data = self.class.stringify(payload)
  end

  def call
    return :invalid if model_id.blank?

    model = VibeModel.find(model_id)
    assert_library!(model)
    key = cache_key

    if skip_fresh?(model, key)
      Rails.logger.info("[CoverGenerator] skip cache_key=#{key} model=#{model.id}")
      return :fresh
    end

    source = resolve_source!(model)
    CoverImage.encode(source, dest_path(model.id), budget)
    writeback_ready!(model, key)
    :ready
  rescue PermanentError => e
    fail!(e)
  rescue *TRANSIENT_ERRNO => e
    raise TransientError, e.message
  end

  def fail!(error)
    return :invalid if model_id.blank?
    return :invalid unless VibeModel.exists?(model_id)

    Rails.logger.warn("[CoverGenerator] failed model=#{model_id}: #{error.class}: #{error.message}")
    CoverWriteback.apply!(
      "model_id" => model_id,
      "asset_id" => @data["asset_id"],
      "status" => VibeModel::COVER_FAILED,
      "cover_placeholder" => true,
      "cache_key" => cache_key
    )
    :failed
  rescue ArgumentError, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => writeback_error
    Rails.logger.warn("[CoverGenerator] writeback failed model=#{model_id}: #{writeback_error.message}")
    :failed
  end

  private

  def model_id
    @data["model_id"].presence
  end

  def cache_key
    self.class.cache_key_for(@data)
  end

  def skip_fresh?(model, key)
    model.cover_status == VibeModel::COVER_READY &&
      model.cover_cache_key.to_s == key &&
      model.cover_url.present?
  end

  def assert_library!(model)
    return if @data["library_id"].blank?
    return if model.library_id.to_i == @data["library_id"].to_i

    raise PermanentError, "library_id does not match model"
  end

  def resolve_source!(model)
    library = model.library
    jail = LibraryPathJail.new(library.root_path)
    jailed = @data["jailed_path"].to_s

    path = resolve_jailed!(jail, jailed)
    return path if image_path?(path)

    # Mesh / archive: use a named preview sibling under the jail when present.
    # Do not unzip, slurp, or rasterize 3D — this worker has no mesh renderer.
    sibling = find_preview_sibling(jail, jailed)
    return sibling if sibling

    raise PermanentError, "no preview image for mesh/archive #{jailed}"
  end

  def resolve_jailed!(jail, jailed)
    jail.resolve_jailed(jailed)
  rescue ArgumentError => e
    raise PermanentError, e.message
  end

  def find_preview_sibling(jail, jailed_path)
    parts = jailed_path.to_s.tr("\\", "/").split("/").reject(&:blank?)
    return if parts.size < 2

    dir = parts[0..-2]
    PREVIEW_STEMS.each do |stem|
      IMAGE_EXT.each do |ext|
        candidate = [*dir, "#{stem}.#{ext}"].join("/")
        begin
          return jail.resolve_jailed(candidate)
        rescue ArgumentError
          next
        end
      end
    end
    nil
  end

  def image_path?(path)
    IMAGE_EXT.include?(File.extname(path.to_s).delete(".").downcase)
  end

  def dest_path(model_id)
    File.join(self.class.cover_root, "#{model_id}.webp")
  end

  def budget
    raw = @data["budget"]
    raw = raw.to_h.stringify_keys if raw.respond_to?(:to_h)
    defaults = CoverEnqueue.budget
    max_px = raw.is_a?(Hash) ? raw["max_px"].to_i : 0
    max_bytes = raw.is_a?(Hash) ? raw["max_bytes"].to_i : 0
    {
      "max_px" => max_px.positive? ? max_px : defaults["max_px"],
      "max_bytes" => max_bytes.positive? ? max_bytes : defaults["max_bytes"]
    }
  end

  def writeback_ready!(model, key)
    CoverWriteback.apply!(
      "model_id" => model.id,
      "asset_id" => @data["asset_id"],
      "status" => VibeModel::COVER_READY,
      "cover_url" => self.class.cover_url_for(model.id),
      "cover_placeholder" => false,
      "cache_key" => key
    )
  end
end
