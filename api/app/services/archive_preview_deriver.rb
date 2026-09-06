require "fileutils"

# Copies a single hot image member into the preview cache.
# Never extracts the rest of the archive.
class ArchivePreviewDeriver
  def initialize(member)
    @member = member
  end

  def derive!
    return :skipped unless @member.hot_image?
    return :exists if @member.preview_file_present?
    return :unavailable unless @member.streamable?

    tmp = ArchiveIndexer.new(@member.asset).extract_member(
      @member.internal_path,
      max_bytes: ArchiveIndexer.preview_bytes
    )
    digest = Digest::SHA256.file(tmp.path).hexdigest
    @member.update!(preview_digest: digest)
    dest = @member.preview_absolute_path(digest)
    FileUtils.mkdir_p(File.dirname(dest))
    FileUtils.cp(tmp.path, dest)
    :ok
  rescue ArgumentError, ActiveRecord::RecordNotFound, ArchiveShellLister::Error => e
    Rails.logger.warn("[ArchivePreviewDeriver] member=#{@member.id}: #{e.message}")
    :failed
  ensure
    tmp&.close!
  end
end
