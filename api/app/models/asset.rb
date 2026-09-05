class Asset < ApplicationRecord
  ARCHIVE_KINDS = %w[zip 7z rar 3mf].freeze
  MESH_KINDS = %w[stl obj 3mf gcode bgcode].freeze

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

  def absolute_path
    File.join(vibe_model.absolute_path, relative_path)
  end
end
