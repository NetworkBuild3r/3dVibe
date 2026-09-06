# Fingerprint hook for Rendering. Stub: path-jails the mesh and no-ops when
# geometry_digest is still blank. Rendering should compute a stable mesh
# digest and write it via GeometryWriteback.apply! or POST /geometry/writeback.
class ComputeGeometryDigestJob < ApplicationJob
  queue_as :duplicates

  discard_on ActiveRecord::RecordNotFound

  def perform(asset_id)
    asset = Asset.find(asset_id)
    return unless asset.mesh?
    return if asset.geometry_digest.present?

    digest = GeometryFingerprint.compute(asset)
    if digest.present?
      GeometryWriteback.apply!(asset_id: asset.id, geometry_digest: digest)
    else
      Rails.logger.info("[ComputeGeometryDigestJob] skip asset=#{asset.id} (digest blank; Rendering hook is a stub)")
    end
  end
end
