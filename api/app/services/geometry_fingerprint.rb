require "zip"

# Mesh-only geometry fingerprint. Path-jails the file, streams STL/OBJ/3MF,
# and returns a stable digest for the same mesh / different bytes (re-exports).
# Non-mesh, jail escape, and budget skips return nil — never write an empty
# digest, never load an archive into RAM, never touch grouping.
class GeometryFingerprint
  FINGERPRINT_KINDS = %w[stl obj 3mf].freeze
  KINDS = FINGERPRINT_KINDS

  attr_reader :skip_reason

  def self.compute(asset, budget: nil)
    new(asset, budget: budget).compute
  end

  def initialize(asset, budget: nil)
    @asset = asset
    @budget = budget || GeometryBudget.from_env
    @skip_reason = nil
  end

  def compute
    @skip_reason = nil
    return skip("already_present") if @asset.geometry_digest.present?
    return skip("non_mesh") unless fingerprintable?
    return skip("too_large") if catalog_oversized?

    path = jailed_file
    return skip("jail") unless path
    return skip("too_large") if file_oversized?(path)

    mesh = GeometryMesh.new(@budget).parse!(path, kind: @asset.kind)
    return skip("empty") if mesh.empty?

    "mesh:v1:#{mesh.hexdigest}"
  rescue GeometryMesh::LimitError => e
    skip(e.reason)
  rescue ArgumentError, Errno::ENOENT, Errno::EACCES, Errno::ESTALE, Errno::EIO
    skip("jail")
  rescue EOFError, Zip::Error
    skip("unreadable")
  end

  private

  def fingerprintable?
    FINGERPRINT_KINDS.include?(@asset.kind.to_s)
  end

  def catalog_oversized?
    @budget.oversized?(@asset.byte_size)
  end

  def file_oversized?(path)
    @budget.oversized?(File.size(path))
  end

  def jailed_file
    model = @asset.vibe_model
    LibraryPathJail.new(model.library.root_path).resolve_file(model.folder_name, @asset.relative_path)
  rescue ArgumentError
    nil
  end

  def skip(reason)
    @skip_reason = reason
    nil
  end
end
