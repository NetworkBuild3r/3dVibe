require "zip"

# Mesh-only geometry fingerprint. Path-jails the file (or parent archive),
# streams STL/OBJ/3MF (one archive member at a time), and returns a stable
# digest for the same mesh / different bytes (re-exports).
# Non-mesh, jail escape, missing member, and budget skips return nil —
# never write an empty digest, never load an archive into RAM, never touch grouping.
class GeometryFingerprint
  FINGERPRINT_KINDS = %w[stl obj 3mf].freeze
  KINDS = FINGERPRINT_KINDS

  attr_reader :skip_reason

  def self.compute(target, budget: nil)
    new(target, budget: budget).compute
  end

  def initialize(target, budget: nil)
    @target = target
    @budget = budget || GeometryBudget.from_env
    @skip_reason = nil
  end

  def compute
    @skip_reason = nil
    return skip("already_present") if @target.geometry_digest.present?
    return skip("non_mesh") unless fingerprintable?
    return skip("too_large") if catalog_oversized?

    path, cleanup = resolve_source
    return unless path

    begin
      return skip("too_large") if file_oversized?(path)

      mesh = GeometryMesh.new(@budget).parse!(path, kind: mesh_kind)
      return skip("empty") if mesh.empty?

      "mesh:v1:#{mesh.hexdigest}"
    ensure
      cleanup&.call
    end
  rescue GeometryMesh::LimitError => e
    skip(e.reason)
  rescue ArgumentError, Errno::ENOENT, Errno::EACCES, Errno::ESTALE, Errno::EIO
    skip("jail")
  rescue EOFError, Zip::Error, ArchiveShellLister::Error
    skip("unreadable")
  end

  private

  def archive_member?
    @target.is_a?(ArchiveMember)
  end

  def fingerprintable?
    if archive_member?
      @target.mesh? && !@target.placeholder?
    else
      FINGERPRINT_KINDS.include?(@target.kind.to_s)
    end
  end

  def catalog_oversized?
    size = archive_member? ? @target.uncompressed_size : @target.byte_size
    @budget.oversized?(size)
  end

  def file_oversized?(path)
    @budget.oversized?(File.size(path))
  end

  def mesh_kind
    archive_member? ? @target.extension : @target.kind
  end

  def resolve_source
    archive_member? ? resolve_member_source : resolve_asset_source
  end

  def resolve_asset_source
    path = jailed_file
    return skip_source("jail") unless path

    [path, nil]
  end

  def resolve_member_source
    archive_path = jailed_archive
    return skip_source("jail") unless archive_path

    tmp = ArchiveIndexer.new(@target.asset).extract_member(
      @target.internal_path,
      max_bytes: stream_limit,
      archive_path: archive_path
    )
    [tmp.path, -> { tmp.close! }]
  rescue ActiveRecord::RecordNotFound
    skip_source("missing")
  rescue ArgumentError => e
    skip_source(member_argument_reason(e))
  rescue ArchiveShellLister::Error, Zip::Error, EOFError
    skip_source("unreadable")
  end

  def skip_source(reason)
    skip(reason)
    nil
  end

  def member_argument_reason(error)
    message = error.message.to_s
    return "too_large" if message.match?(/oversized/i)
    return "non_mesh" if message.match?(/directory/i)
    return "jail" if message.match?(/unsafe|missing|escape|invalid path|empty path/i)

    "unreadable"
  end

  def stream_limit
    stream = ArchiveIndexer.stream_bytes
    geo = @budget.max_bytes
    return stream unless geo.positive?

    [stream, geo].min
  end

  def jailed_file
    model = @target.vibe_model
    LibraryPathJail.new(model.library.root_path).resolve_file(model.folder_name, @target.relative_path)
  rescue ArgumentError
    nil
  end

  def jailed_archive
    asset = @target.asset
    model = asset.vibe_model
    LibraryPathJail.new(model.library.root_path).resolve_file(model.folder_name, asset.relative_path)
  rescue ArgumentError, Errno::ENOENT, Errno::EACCES, Errno::ESTALE
    nil
  end

  def skip(reason)
    @skip_reason = reason
    nil
  end
end
