class ArchiveMember < ApplicationRecord
  belongs_to :asset

  MESH_EXTENSIONS = %w[stl obj 3mf].freeze
  IMAGE_EXTENSIONS = %w[png jpg jpeg webp gif].freeze
  TEXT_EXTENSIONS = %w[txt md].freeze
  PREVIEW_EXTENSIONS = (MESH_EXTENSIONS + IMAGE_EXTENSIONS + TEXT_EXTENSIONS).freeze
  PLACEHOLDER_PATH = "(listing pending)"

  CONTENT_TYPES = {
    "stl" => "model/stl",
    "obj" => "model/obj",
    "3mf" => "model/3mf",
    "gcode" => "text/plain",
    "bgcode" => "application/octet-stream",
    "png" => "image/png",
    "jpg" => "image/jpeg",
    "jpeg" => "image/jpeg",
    "webp" => "image/webp",
    "gif" => "image/gif",
    "txt" => "text/plain",
    "md" => "text/markdown",
    "xml" => "application/xml",
    "json" => "application/json",
    "html" => "text/html"
  }.freeze

  validates :internal_path, presence: true, uniqueness: { scope: :asset_id }

  before_validation :assign_derived_fields

  def self.content_type_for(extension)
    CONTENT_TYPES[extension.to_s.delete(".").downcase]
  end

  def self.normalize_path(path, directory: false)
    cleaned = path.to_s.tr("\\", "/").delete_prefix("./")
    cleaned = cleaned.gsub(%r{/+}, "/")
    parts = cleaned.split("/").reject { |part| part.blank? || part == "." }
    raise ArgumentError, "unsafe archive path" if parts.include?("..")
    return "" if parts.empty?

    joined = parts.join("/")
    directory || cleaned.end_with?("/") ? "#{joined}/" : joined
  end

  def self.normalize_prefix(prefix)
    return "" if prefix.blank?

    normalize_path(prefix, directory: true)
  end

  def self.parent_of(path)
    parts = normalize_path(path).delete_suffix("/").split("/")
    return "" if parts.size <= 1

    "#{parts[0..-2].join("/")}/"
  end

  def self.basename_of(path)
    normalize_path(path).delete_suffix("/").split("/").last.to_s
  end

  def self.preview_root
    ENV.fetch("VIBE_PREVIEW_ROOT", Rails.root.join("tmp/previews").to_s)
  end

  def self.preview_bytes
    Integer(ENV.fetch("VIBE_ARCHIVE_PREVIEW_BYTES", 4.megabytes))
  end

  def previewable?
    PREVIEW_EXTENSIONS.include?(extension)
  end

  def extension
    File.extname(internal_path.to_s.delete_suffix("/")).delete(".").downcase
  end

  def mesh?
    MESH_EXTENSIONS.include?(extension) && !directory?
  end

  def image?
    IMAGE_EXTENSIONS.include?(extension) && !directory?
  end

  def placeholder?
    listing_source == "placeholder" || internal_path == PLACEHOLDER_PATH
  end

  def streamable?
    return false if directory? || placeholder?

    asset.streamable_archive?
  end

  def has_preview?
    return true if preview_file_present?
    return true if image? && streamable? && uncompressed_size.to_i.positive? && uncompressed_size.to_i <= self.class.preview_bytes

    false
  end

  def preview_file_present?
    preview_digest.present? && File.file?(preview_absolute_path)
  end

  def preview_absolute_path(digest = preview_digest)
    return if digest.blank?

    File.join(self.class.preview_root, "members", id.to_s, "#{digest}#{File.extname(internal_path)}")
  end

  def depth
    parent_path.to_s.count("/")
  end

  def hot_image?
    image? && uncompressed_size.to_i.positive? && uncompressed_size.to_i <= self.class.preview_bytes
  end

  private

  def assign_derived_fields
    self.internal_path = self.class.normalize_path(internal_path, directory: directory?) if internal_path.present?
    self.parent_path = self.class.parent_of(internal_path)
    self.basename = self.class.basename_of(internal_path)
    self.content_type = self.class.content_type_for(extension)
    self.listing_source = listing_source.presence || "zip"
  end
end
