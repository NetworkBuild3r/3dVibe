require "timeout"
require "zip"

# Stream one archive member (zip / 3mf / 7z / rar) in 64 KiB chunks.
# Path-jails the parent archive. Never extracts the pack to NFS or RAM.
# HTTP uses #each so a client abort (SPA navigate-away) closes the zip/7z
# handle instead of leaving a whole-member tempfile.
class ArchiveMemberStreamer
  CHUNK = ArchiveIndexer::CHUNK
  RangeSpec = Struct.new(:first, :last, :total, :length, keyword_init: true)

  def self.stream_bytes
    ArchiveIndexer.stream_bytes
  end

  def self.preview_bytes
    ArchiveIndexer.preview_bytes
  end

  def self.stream_seconds
    ArchiveIndexer.stream_seconds
  end

  def self.for_member(member, archive_path: nil)
    new(member.asset, member.internal_path, archive_path: archive_path, size_hint: member.uncompressed_size)
  end

  def self.jailed_archive_path(asset)
    model = asset.vibe_model
    LibraryPathJail.new(model.library.root_path).resolve_file(model.folder_name, asset.relative_path)
  end

  def self.parse_range(header, total:)
    return if header.blank? || total.nil? || total <= 0

    raw = header.to_s
    return unless raw.match?(/\Abytes=/i)

    spec = raw.sub(/\Abytes=/i, "")
    return :unsatisfiable if spec.include?(",")

    if spec.start_with?("-")
      suffix = Integer(spec[1..], exception: false)
      return :unsatisfiable if suffix.nil? || suffix <= 0

      first = [total - suffix, 0].max
      last = total - 1
    else
      start_s, end_s = spec.split("-", 2)
      first = Integer(start_s, exception: false)
      return :unsatisfiable if first.nil? || first.negative? || first >= total

      last = end_s.present? ? Integer(end_s, exception: false) : (total - 1)
      return :unsatisfiable if last.nil? || last < first

      last = [last, total - 1].min
    end

    RangeSpec.new(first: first, last: last, total: total, length: last - first + 1)
  rescue ArgumentError
    :unsatisfiable
  end

  def initialize(asset, internal_path, archive_path: nil, size_hint: nil)
    @asset = asset
    @internal_path = ArchiveMember.normalize_path(internal_path)
    raise ArgumentError, "Cannot stream a directory" if @internal_path.end_with?("/")

    @size_hint = size_hint&.to_i
    @archive_path = resolve_archive_path(archive_path)
  end

  def known_size
    return @known_size if defined?(@known_size)

    @known_size =
      case @asset.kind
      when "zip", "3mf"
        with_zip_entry { |entry| entry.size.to_i }
      else
        @size_hint&.positive? ? @size_hint : nil
      end
  end

  def each(max_bytes: self.class.stream_bytes, max_seconds: self.class.stream_seconds, offset: 0, length: nil)
    raise ArgumentError, "Refusing to load oversized member" if known_size && known_size > max_bytes

    with_time_budget(max_seconds) do
      case @asset.kind
      when "zip", "3mf"
        stream_zip(max_bytes: max_bytes, offset: offset, length: length) { |chunk| yield chunk }
      when "7z", "rar"
        stream_shell(max_bytes: max_bytes, offset: offset, length: length) { |chunk| yield chunk }
      else
        raise ArgumentError, "Only zip-family archives can stream a member"
      end
    end
  rescue IOError, Errno::EPIPE, Errno::ECONNRESET
    nil
  end

  def extract_tempfile(max_bytes: self.class.stream_bytes, max_seconds: self.class.stream_seconds)
    tmp = Tempfile.new(["archive-member", File.extname(@internal_path)])
    tmp.binmode
    each(max_bytes: max_bytes, max_seconds: max_seconds) { |chunk| tmp.write(chunk) }
    tmp.flush
    tmp.rewind
    tmp
  rescue StandardError
    tmp&.close! if tmp && !tmp.closed?
    raise
  end

  private

  def resolve_archive_path(archive_path)
    path =
      if archive_path.present?
        archive_path.to_s
      else
        self.class.jailed_archive_path(@asset).to_s
      end
    raise ArgumentError, "archive missing on disk" unless File.file?(path)

    model = @asset.vibe_model
    if model&.library&.root_path
      LibraryPathJail.new(model.library.root_path).assert_realpath_inside!(path)
    end
    path
  end

  def with_time_budget(max_seconds)
    limit = max_seconds.to_f
    return yield if limit <= 0

    Timeout.timeout(limit) { yield }
  rescue Timeout::Error
    raise ArgumentError, "Archive member stream timed out"
  end

  def stream_zip(max_bytes:, offset:, length:)
    with_zip_entry do |entry|
      raise ArgumentError, "Cannot stream a directory" if entry.directory?
      raise ArgumentError, "Refusing to load oversized member" if entry.size && entry.size > max_bytes

      copy_limited(entry.get_input_stream, max_bytes: max_bytes, offset: offset, length: length) { |chunk| yield chunk }
    end
  end

  def stream_shell(max_bytes:, offset:, length:)
    raise ArgumentError, "7z/rar streaming needs the 7z CLI" unless ArchiveShellLister.available?

    skipped = 0
    emitted = 0
    ArchiveShellLister.new(@archive_path).stream_member(
      @internal_path,
      max_bytes: max_bytes,
      max_seconds: 0
    ) do |chunk|
      take = take_from_chunk(chunk, skipped: skipped, offset: offset, emitted: emitted, length: length)
      skipped = take[:skipped]
      next if take[:payload].blank?

      emitted += take[:payload].bytesize
      yield take[:payload]
      break if length && emitted >= length
    end
  end

  def take_from_chunk(chunk, skipped:, offset:, emitted:, length:)
    remaining_skip = [offset - skipped, 0].max
    if remaining_skip >= chunk.bytesize
      return { skipped: skipped + chunk.bytesize, payload: nil }
    end

    usable = remaining_skip.positive? ? chunk.byteslice(remaining_skip..) : chunk
    skipped += remaining_skip
    if length
      keep = length - emitted
      usable = usable.byteslice(0, keep) if usable.bytesize > keep
    end
    { skipped: skipped, payload: usable }
  end

  def copy_limited(io, max_bytes:, offset:, length:)
    skip_bytes(io, offset)
    remaining = length || (max_bytes + 1)
    copied = 0
    buffer = String.new(capacity: CHUNK)
    while remaining.positive? && (chunk = io.read([CHUNK, remaining].min, buffer))
      copied += chunk.bytesize
      raise ArgumentError, "Refusing to load oversized member" if copied + offset > max_bytes

      yield chunk.dup
      remaining -= chunk.bytesize
    end
  end

  def skip_bytes(io, offset)
    left = offset.to_i
    buffer = String.new(capacity: CHUNK)
    while left.positive? && (chunk = io.read([CHUNK, left].min, buffer))
      left -= chunk.bytesize
    end
  end

  def with_zip_entry
    Zip::File.open(@archive_path) do |zip|
      entry = find_zip_entry(zip)
      raise ActiveRecord::RecordNotFound, "Missing archive member" unless entry

      yield entry
    end
  end

  def find_zip_entry(zip)
    zip.find_entry(@internal_path) ||
      zip.find_entry(@internal_path.delete_suffix("/")) ||
      zip.find_entry(@internal_path.tr("/", "\\"))
  end
end
