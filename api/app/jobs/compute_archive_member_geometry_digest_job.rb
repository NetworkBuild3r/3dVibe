# Stub for Rendering. Path-jails the parent archive + member path only.
# Does not stream zip members, extract to disk, or write a digest.
# Rendering fills this by streaming one member and calling GeometryWriteback.
class ComputeArchiveMemberGeometryDigestJob < ApplicationJob
  queue_as :duplicates

  discard_on ActiveRecord::RecordNotFound

  def perform(archive_member_id)
    member = ArchiveMember.find(archive_member_id)
    return if member.geometry_digest.present?
    return unless member.mesh?
    return if member.directory? || member.placeholder?

    path = jailed_archive(member)
    unless path
      Rails.logger.info("[ComputeArchiveMemberGeometryDigestJob] skip archive_member=#{member.id} reason=jail")
      return
    end

    Rails.logger.info(
      "[ComputeArchiveMemberGeometryDigestJob] awaiting rendering " \
      "archive_member=#{member.id} archive=#{path} member_path=#{member.internal_path}"
    )
  end

  private

  def jailed_archive(member)
    asset = member.asset
    model = asset.vibe_model
    LibraryPathJail.new(model.library.root_path).resolve_file(model.folder_name, asset.relative_path)
  rescue ArgumentError, Errno::ENOENT, Errno::EACCES, Errno::ESTALE
    nil
  end
end
