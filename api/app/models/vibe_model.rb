class VibeModel < ApplicationRecord
  COVER_MISSING = "missing"
  COVER_PENDING = "pending"
  COVER_READY = "ready"
  COVER_FAILED = "failed"
  COVER_STATUSES = [COVER_MISSING, COVER_PENDING, COVER_READY, COVER_FAILED].freeze
  CARD_INCLUDES = [:tags, :library, :uploaded_by, :creator, :assets].freeze

  belongs_to :library
  belongs_to :uploaded_by, class_name: "User", optional: true
  belongs_to :creator, optional: true

  has_many :assets, dependent: :destroy
  has_many :archive_members, through: :assets
  has_many :tag_assignments, as: :taggable, dependent: :destroy
  has_many :tags, through: :tag_assignments
  has_many :print_dispatches, dependent: :nullify
  has_many :likes, dependent: :destroy
  has_many :bookmarks, dependent: :destroy
  has_many :model_merges, foreign_key: :target_vibe_model_id, inverse_of: :target_vibe_model, dependent: :destroy

  validates :folder_name, presence: true, uniqueness: { scope: :library_id }
  validates :title, presence: true
  validates :cover_status, inclusion: { in: COVER_STATUSES }

  scope :recent, -> { order(updated_at: :desc, id: :desc) }
  scope :for_cards, -> { includes(*CARD_INCLUDES) }

  after_commit :enqueue_search_index, on: %i[create update]
  after_commit :enqueue_search_removal, on: :destroy

  def absolute_path
    File.join(library.root_path, folder_name)
  end

  def has_cover?
    cover_status == COVER_READY
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
      has_preview: previewable?,
      creator: creator&.as_card,
      cover_status: cover_status,
      cover_url: cover_url,
      cover_lqip_url: cover_lqip_url,
      cover_placeholder: cover_placeholder
    }
  end

  def self.card_payloads(models, viewer: nil)
    models = Array(models)
    ids = models.map(&:id)
    like_counts = Like.where(vibe_model_id: ids).group(:vibe_model_id).count
    liked_ids = viewer ? Like.where(user_id: viewer.id, vibe_model_id: ids).pluck(:vibe_model_id).to_set : Set.new
    folder_map = Hash.new { |hash, key| hash[key] = [] }
    if viewer
      Bookmark.where(user_id: viewer.id, vibe_model_id: ids).pluck(:vibe_model_id, :bookmark_folder_id).each do |model_id, folder_id|
        folder_map[model_id] << folder_id
      end
    end
    merged_ids = ModelMerge.active.where(target_vibe_model_id: ids).pluck(:target_vibe_model_id).to_set

    models.map do |model|
      model.as_card.merge(
        liked: liked_ids.include?(model.id),
        like_count: like_counts[model.id] || 0,
        bookmark_folder_ids: folder_map[model.id],
        merged: merged_ids.include?(model.id)
      )
    end
  end

  private

  def enqueue_search_index
    SearchIndex.enqueue(self)
  end

  def enqueue_search_removal
    SearchIndex.enqueue_remove(id)
  end
end

