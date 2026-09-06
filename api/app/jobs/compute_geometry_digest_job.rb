# Path-jailed mesh fingerprint. Writes assets.geometry_digest via
# GeometryWriteback.apply! so DuplicateAnalyzer can cluster geometry groups.
# Skips / times out huge meshes without slurping archives.
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
      Rails.logger.info("[ComputeGeometryDigestJob] skip asset=#{asset.id} (digest blank)")
    end
  end
end
