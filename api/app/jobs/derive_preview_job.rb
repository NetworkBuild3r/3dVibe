class DerivePreviewJob < ApplicationJob
  queue_as :previews

  # Stub: later this would rasterize a still or decimate a mesh.
  def perform(asset_id)
    asset = Asset.find_by(id: asset_id)
    return unless asset

    Rails.logger.info("[DerivePreviewJob] queued preview derivation for asset=#{asset.id} path=#{asset.relative_path}")
  end
end
