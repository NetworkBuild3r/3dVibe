class VibeModel < ApplicationRecord
  belongs_to :library
  belongs_to :uploaded_by, class_name: "User", optional: true

  has_many :assets, dependent: :destroy
  has_many :archive_members, through: :assets
  has_many :tag_assignments, as: :taggable, dependent: :destroy
  has_many :tags, through: :tag_assignments

  validates :folder_name, presence: true, uniqueness: { scope: :library_id }
  validates :title, presence: true

  scope :recent, -> { order(updated_at: :desc, id: :desc) }

  def absolute_path
    File.join(library.root_path, folder_name)
  end
end
