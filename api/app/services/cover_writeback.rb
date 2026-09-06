# Job/API hook for the Rendering worker. Sets cover_status ready/failed plus
# cover_url after a budgeted generate. Does not open or rasterize files.
class CoverWriteback
  ALLOWED = [VibeModel::COVER_READY, VibeModel::COVER_FAILED].freeze

  def self.apply!(attrs)
    new(attrs).apply!
  end

  def initialize(attrs)
    @attrs = attrs.respond_to?(:to_unsafe_h) ? attrs.to_unsafe_h : attrs
    @attrs = @attrs.to_h.stringify_keys
  end

  def apply!
    model = VibeModel.find(model_id)
    status = @attrs["status"].to_s
    raise ArgumentError, "status must be ready or failed" unless ALLOWED.include?(status)

    url = @attrs["cover_url"].to_s.presence
    raise ArgumentError, "cover_url is required when status=ready" if status == VibeModel::COVER_READY && url.blank?

    placeholder = if @attrs.key?("cover_placeholder")
      ActiveModel::Type::Boolean.new.cast(@attrs["cover_placeholder"])
    else
      status != VibeModel::COVER_READY
    end

    updates = {
      cover_status: status,
      cover_url: status == VibeModel::COVER_READY ? url : url,
      cover_placeholder: placeholder
    }
    updates[:cover_asset_id] = @attrs["asset_id"].to_i if @attrs["asset_id"].present?
    updates[:cover_cache_key] = @attrs["cache_key"].to_s if @attrs["cache_key"].present?
    model.update!(updates)
    # after_commit also enqueues; the buffer collapses both so has_cover /
    # cover_status land in Meili without an IndexVibeModelJob per write-back.
    SearchIndex.enqueue(model)
    model
  end

  private

  def model_id
    id = @attrs["model_id"].presence || @attrs["id"]
    raise ArgumentError, "model_id is required" if id.blank?

    id
  end
end
