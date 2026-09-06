# Mesh fingerprint hook for Rendering. This backend never computes a real
# geometry digest — it only path-jails the file so a future worker can stream
# it. Archives are never loaded into RAM. Returns nil until Rendering fills in.
class GeometryFingerprint
  def self.compute(asset)
    new(asset).compute
  end

  def initialize(asset)
    @asset = asset
  end

  def compute
    return if @asset.geometry_digest.present?
    return unless @asset.mesh?

    jail.resolve_file(@asset.vibe_model.folder_name, @asset.relative_path)
    nil
  rescue ArgumentError, Errno::ENOENT, Errno::EACCES, Errno::ESTALE
    nil
  end

  private

  def jail
    LibraryPathJail.new(@asset.vibe_model.library.root_path)
  end
end
