# Mesh-only geometry fingerprint for one archive member. Path-jails the
# parent zip/7z/rar/3mf, streams that member only (never the whole archive),
# and writes archive_members.geometry_digest via GeometryWriteback.apply!.
# Skips (no crash, no empty digest) on jail escape, missing member, non-mesh,
# or budget.
class ComputeArchiveMemberGeometryDigestJob < ApplicationJob
  queue_as :duplicates

  discard_on ActiveRecord::RecordNotFound

  def perform(archive_member_id)
    member = ArchiveMember.find(archive_member_id)
    return if member.geometry_digest.present?
    return unless member.mesh?
    return if member.directory? || member.placeholder?

    fingerprint = GeometryFingerprint.new(member)
    digest = fingerprint.compute
    if digest.present?
      GeometryWriteback.apply!(archive_member_id: member.id, geometry_digest: digest)
    else
      Rails.logger.info("[ComputeArchiveMemberGeometryDigestJob] skip archive_member=#{member.id} reason=#{fingerprint.skip_reason || 'blank'}")
    end
  end
end
