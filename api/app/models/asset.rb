class Asset < ApplicationRecord
  ARCHIVE_KINDS = %w[zip 7z rar 3mf].freeze
  MESH_KINDS = %w[stl obj 3mf gcode bgcode].freeze
  IMAGE_KINDS = %w[png jpg jpeg webp gif].freeze
  ZIP_FAMILY = %w[zip 3mf].freeze
  SHELL_FAMILY = %w[7z rar].freeze
  ARCHIVE_SUPPORT_FULL = "full"
  ARCHIVE_SUPPORT_BEST_EFFORT = "best_effort"
  ARCHIVE_SUPPORT_PLACEHOLDER = "placeholder"

  belongs_to :vibe_model
  belongs_to :uploaded_by, class_name: "User", optional: true
  has_many :archive_members, dependent: :destroy

  validates :relative_path, presence: true, uniqueness: { scope: :vibe_model_id }

  def archive?
    ARCHIVE_KINDS.include?(kind)
  end

  def mesh?
    MESH_KINDS.include?(kind)
  end

  def image?
    IMAGE_KINDS.include?(kind)
  end

  def zip_family?
    ZIP_FAMILY.include?(kind)
  end

  def streamable_archive?
    return true if zip_family?
    return true if SHELL_FAMILY.include?(kind) && ArchiveShellLister.available?

    false
  end

  def absolute_path
    File.join(vibe_model.absolute_path, relative_path)
  end
end
