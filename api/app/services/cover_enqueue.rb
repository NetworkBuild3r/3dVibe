# Enqueues a budgeted cover job. GenerateCoverJob generates and writes back.
class CoverEnqueue
  DEFAULT_MAX_PX = 512
  DEFAULT_MAX_BYTES = 250_000
  CANDIDATE_NAME = /cover|preview|thumb|hero/i
  RANK = { "cover" => 0, "preview" => 1, "thumb" => 2, "hero" => 3 }.freeze

  def self.call(model)
    new(model).call
  end

  def initialize(model)
    @model = model
  end

  def call
    asset = pick_candidate
    unless asset
      clear_missing! unless @model.cover_status == VibeModel::COVER_MISSING
      return :missing
    end

    key = cache_key(asset)
    if @model.cover_status == VibeModel::COVER_READY && @model.cover_cache_key == key && @model.cover_url.present?
      return :fresh
    end
    if @model.cover_status == VibeModel::COVER_PENDING && @model.cover_cache_key == key
      return :pending
    end

    @model.update!(
      cover_status: VibeModel::COVER_PENDING,
      cover_placeholder: true,
      cover_cache_key: key,
      cover_asset_id: asset.id
    )
    GenerateCoverJob.perform_later(payload(asset))
    :enqueued
  end

  def self.cache_key_for(asset)
    hash = content_hash_for(asset)
    "#{asset.id}:#{asset.mtime.to_i}:#{hash}"
  end

  def self.content_hash_for(asset)
    digest = asset.content_digest.to_s
    return if digest.blank?

    digest.start_with?("sha256:") ? digest : "sha256:#{digest}"
  end

  def self.budget
    {
      "max_px" => ENV.fetch("VIBE_COVER_MAX_PX", DEFAULT_MAX_PX).to_i,
      "max_bytes" => ENV.fetch("VIBE_COVER_MAX_BYTES", DEFAULT_MAX_BYTES).to_i
    }
  end

  def self.jailed_path_for(model, asset)
    [model.folder_name, asset.relative_path].join("/")
  end

  private

  def pick_candidate
    assets = @model.assets.to_a
    images = assets.select(&:image?)
    named = images.select { |asset| CANDIDATE_NAME.match?(asset.filename) || CANDIDATE_NAME.match?(asset.relative_path) }
    ranked = named.min_by { |asset| [name_rank(asset), asset.relative_path] }
    return ranked if ranked
    return images.min_by(&:relative_path) if images.any?

    assets.select(&:mesh?).min_by(&:relative_path)
  end

  def name_rank(asset)
    haystack = "#{asset.filename} #{asset.relative_path}".downcase
    RANK.each { |token, rank| return rank if haystack.include?(token) }
    9
  end

  def cache_key(asset)
    self.class.cache_key_for(asset)
  end

  def payload(asset)
    {
      "library_id" => @model.library_id,
      "model_id" => @model.id,
      "asset_id" => asset.id,
      "jailed_path" => self.class.jailed_path_for(@model, asset),
      "mtime" => asset.mtime.to_i,
      "content_hash" => self.class.content_hash_for(asset),
      "budget" => self.class.budget
    }
  end

  def clear_missing!
    @model.update!(
      cover_status: VibeModel::COVER_MISSING,
      cover_url: nil,
      cover_placeholder: true,
      cover_cache_key: nil,
      cover_asset_id: nil
    )
  end
end
