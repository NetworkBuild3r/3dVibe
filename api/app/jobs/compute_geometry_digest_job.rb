# Mesh-only geometry fingerprint. Path-jails the file, streams STL/OBJ/3MF,
# and writes assets.geometry_digest via GeometryWriteback.apply!.
# Skips (no crash, no empty digest) on jail escape, non-mesh, or budget.
class ComputeGeometryDigestJob < ApplicationJob
  queue_as :duplicates

  discard_on ActiveRecord::RecordNotFound

  def perform(asset_id)
    asset = Asset.find(asset_id)
    return unless asset.mesh?
    return if asset.geometry_digest.present?

    fingerprint = GeometryFingerprint.new(asset)
    digest = fingerprint.compute
    if digest.present?
      GeometryWriteback.apply!(asset_id: asset.id, geometry_digest: digest)
    else
      Rails.logger.info("[ComputeGeometryDigestJob] skip asset=#{asset.id} reason=#{fingerprint.skip_reason || 'blank'}")
    end
  end
end
