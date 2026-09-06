class DerivePreviewJob < ApplicationJob
  queue_as :previews

  HOT_LIMIT = 24
  HOT_NAME = /preview|thumb|cover|hero|pack/i

  def perform(asset_id)
    asset = Asset.find_by(id: asset_id)
    return unless asset

    if asset.archive?
      derive_archive(asset)
    else
      Rails.logger.info("[DerivePreviewJob] queued preview derivation for asset=#{asset.id} path=#{asset.relative_path}")
    end
  end

  private

  def derive_archive(asset)
    ranked = asset.archive_members.select(&:hot_image?).sort_by do |member|
      [HOT_NAME.match?(member.basename) || HOT_NAME.match?(member.internal_path) ? 0 : 1, member.depth, member.internal_path]
    end
    ranked.first(HOT_LIMIT).each { |member| ArchivePreviewDeriver.new(member).derive! }
  end
end
