# Job/API hook for the Rendering worker. Sets assets.geometry_digest.
# Does not open or hash files. Near-dup grouping stays HITL (re-run analyze).
class GeometryWriteback
  def self.apply!(attrs)
    new(attrs).apply!
  end

  def initialize(attrs)
    @attrs = attrs.respond_to?(:to_unsafe_h) ? attrs.to_unsafe_h : attrs
    @attrs = @attrs.to_h.stringify_keys
  end

  def apply!
    digest = @attrs["geometry_digest"].to_s.strip
    raise ArgumentError, "geometry_digest is required" if digest.blank?

    asset = Asset.find(asset_id)
    asset.update!(geometry_digest: digest)
    asset
  end

  private

  def asset_id
    id = @attrs["asset_id"].presence || @attrs["id"]
    raise ArgumentError, "asset_id is required" if id.blank?

    id
  end
end
