# Job/API hook for the Rendering worker. Sets geometry_digest on an Asset
# or ArchiveMember. Does not open or hash files. Near-dup grouping stays HITL
# (re-run analyze). Exactly one of asset_id | archive_member_id.
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

    if archive_member_id && asset_id
      raise ArgumentError, "provide exactly one of asset_id or archive_member_id"
    end

    if archive_member_id
      member = ArchiveMember.find(archive_member_id)
      member.update!(geometry_digest: digest)
      return member
    end

    asset = Asset.find(require_asset_id)
    asset.update!(geometry_digest: digest)
    asset
  end

  private

  def archive_member_id
    @attrs["archive_member_id"].presence
  end

  def asset_id
    @attrs["asset_id"].presence || @attrs["id"]
  end

  def require_asset_id
    raise ArgumentError, "asset_id or archive_member_id is required" if asset_id.blank?

    asset_id
  end
end
