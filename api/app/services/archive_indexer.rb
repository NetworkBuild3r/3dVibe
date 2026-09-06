require "zip"

class ArchiveIndexer
  CHUNK = 64 * 1024
  DEFAULT_MEMBER_LIMIT = 10_000
  DEFAULT_STREAM_BYTES = 32.megabytes
  DEFAULT_PREVIEW_BYTES = 4.megabytes

  def self.member_limit
    Integer(ENV.fetch("VIBE_ARCHIVE_MEMBER_LIMIT", DEFAULT_MEMBER_LIMIT))
  end

  def self.stream_bytes
    Integer(ENV.fetch("VIBE_ARCHIVE_STREAM_BYTES", DEFAULT_STREAM_BYTES))
  end

  def self.preview_bytes
    ArchiveMember.preview_bytes
  end

  def self.stream_seconds
    Integer(ENV.fetch("VIBE_ARCHIVE_STREAM_SECONDS", "30"))
  end

  def initialize(asset)
    @asset = asset
  end

  def index!
    path = @asset.absolute_path
    return unless File.file?(path)

    case @asset.kind
    when "zip", "3mf"
      index_zip(path)
    when "7z", "rar"
      index_shell_archive(path)
    end
  end

  def stream_member(internal_path, max_bytes: self.class.stream_bytes)
    tmp = extract_member(internal_path, max_bytes: max_bytes)
    yield tmp
    tmp
  end

  # Stream one member into a Tempfile (fingerprint / derived preview).
  # HTTP open/preview uses ArchiveMemberStreamer#each — no whole-member buffer.
  # Pass archive_path when the caller already path-jailed the parent archive.
  def extract_member(internal_path, max_bytes: self.class.stream_bytes, archive_path: nil)
    ArchiveMemberStreamer.new(@asset, internal_path, archive_path: archive_path)
                         .extract_tempfile(max_bytes: max_bytes)
  end

  private

  def index_zip(path)
    seen = []
    file_count = 0
    limit = self.class.member_limit

    Zip::File.open(path) do |zip|
      zip.each do |entry|
        directory = entry.directory?
        next if !directory && file_count >= limit

        internal = safe_internal_path(entry.name, directory: directory)
        next if internal.blank?

        seen.concat(ensure_parents!(internal))
        seen << persist_member!(
          internal_path: internal,
          directory: directory || internal.end_with?("/"),
          compressed_size: entry.compressed_size,
          uncompressed_size: entry.size,
          mtime: safe_time(entry.time),
          listing_source: "zip"
        )
        file_count += 1 unless directory || internal.end_with?("/")
      end
    end

    finish_index!(seen, truncated: file_count >= limit, support: Asset::ARCHIVE_SUPPORT_FULL)
  rescue Zip::Error, Zlib::Error => e
    Rails.logger.warn("[ArchiveIndexer] zip failed asset=#{@asset.id}: #{e.class}: #{e.message}")
    index_placeholder
  end

  def index_shell_archive(path)
    lister = ArchiveShellLister.new(path)
    unless lister.available?
      index_placeholder
      return
    end

    seen = []
    file_count = 0
    limit = self.class.member_limit

    lister.each_entry do |entry|
      directory = entry.directory
      next if !directory && file_count >= limit

      internal = safe_internal_path(entry.path, directory: directory)
      next if internal.blank?

      seen.concat(ensure_parents!(internal))
      seen << persist_member!(
        internal_path: internal,
        directory: directory || internal.end_with?("/"),
        compressed_size: entry.compressed_size,
        uncompressed_size: entry.size,
        mtime: entry.mtime,
        listing_source: "7z"
      )
      file_count += 1 unless directory || internal.end_with?("/")
    end

    if seen.empty?
      index_placeholder
      return
    end

    finish_index!(seen, truncated: file_count >= limit, support: Asset::ARCHIVE_SUPPORT_BEST_EFFORT)
  rescue ArchiveShellLister::Error, ArgumentError => e
    Rails.logger.warn("[ArchiveIndexer] 7z/rar listing failed asset=#{@asset.id}: #{e.message}")
    index_placeholder
  end

  def index_placeholder
    path = persist_member!(
      internal_path: ArchiveMember::PLACEHOLDER_PATH,
      directory: false,
      compressed_size: File.size?(@asset.absolute_path),
      uncompressed_size: File.size?(@asset.absolute_path),
      mtime: File.file?(@asset.absolute_path) ? File.mtime(@asset.absolute_path) : nil,
      listing_source: "placeholder"
    )
    @asset.archive_members.where.not(internal_path: path).delete_all
    @asset.update!(archive_truncated: false, archive_support: Asset::ARCHIVE_SUPPORT_PLACEHOLDER)
  end

  def finish_index!(seen, truncated:, support:)
    @asset.update!(archive_truncated: truncated, archive_support: support)
    @asset.archive_members.where.not(internal_path: seen).delete_all
  end

  def ensure_parents!(internal_path)
    parts = internal_path.delete_suffix("/").split("/")
    return [] if parts.size <= 1

    created = []
    prefix = +""
    parts[0..-2].each do |segment|
      prefix << "#{segment}/"
      created << persist_member!(
        internal_path: prefix.dup,
        directory: true,
        compressed_size: 0,
        uncompressed_size: 0,
        mtime: nil,
        listing_source: @asset.zip_family? ? "zip" : "7z"
      )
    end
    created
  end

  def persist_member!(attrs)
    internal = ArchiveMember.normalize_path(attrs[:internal_path], directory: attrs[:directory])
    member = @asset.archive_members.find_or_initialize_by(internal_path: internal)
    member.assign_attributes(attrs.merge(internal_path: internal))
    member.save!
    member.internal_path
  end

  def safe_internal_path(name, directory:)
    ArchiveMember.normalize_path(name, directory: directory)
  rescue ArgumentError
    nil
  end

  def safe_time(value)
    value.is_a?(Time) ? value : nil
  rescue StandardError
    nil
  end
end
