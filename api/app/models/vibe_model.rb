class VibeModel < ApplicationRecord
  belongs_to :library
  belongs_to :uploaded_by, class_name: "User", optional: true

  has_many :assets, dependent: :destroy
  has_many :archive_members, through: :assets
  has_many :tag_assignments, as: :taggable, dependent: :destroy
  has_many :tags, through: :tag_assignments
  has_many :print_dispatches, dependent: :nullify

  validates :folder_name, presence: true, uniqueness: { scope: :library_id }
  validates :title, presence: true

  scope :recent, -> { order(updated_at: :desc, id: :desc) }

  after_commit :enqueue_search_index, on: %i[create update]
  after_commit :enqueue_search_removal, on: :destroy

  def absolute_path
    File.join(library.root_path, folder_name)
  end

  def previewable?
    if association(:assets).loaded?
      return true if assets.any?(&:mesh?)
    elsif assets.where(kind: Asset::MESH_KINDS).exists?
      return true
    end

    archive_members.any?(&:previewable?)
  end

  def as_card
    {
      id: id,
      title: title,
      folder_name: folder_name,
      synopsis: synopsis,
      asset_count: asset_count,
      byte_size: byte_size,
      library_id: library_id,
      library_name: library.name,
      tags: tags.map(&:name),
      updated_at: updated_at,
      uploaded_by: uploaded_by && { id: uploaded_by.id, display_name: uploaded_by.display_name },
      has_preview: previewable?
    }
  end

  private

  def enqueue_search_index
    SearchIndex.enqueue(self)
  end

  def enqueue_search_removal
    SearchIndex.enqueue_remove(id)
  end
end

