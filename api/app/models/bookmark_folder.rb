class BookmarkFolder < ApplicationRecord
  belongs_to :user
  has_many :bookmarks, dependent: :destroy
  has_many :vibe_models, through: :bookmarks

  validates :name, presence: true, uniqueness: { scope: :user_id, case_sensitive: false }
  validates :position, numericality: { only_integer: true }

  scope :ordered, -> { order(:position, :name, :id) }

  def as_api(include_models: false)
    payload = {
      id: id,
      name: name,
      position: position,
      bookmark_count: bookmarks.size,
      created_at: created_at,
      updated_at: updated_at
    }
    return payload unless include_models

    payload.merge(models: vibe_models.for_cards.map { |model| model.as_card })
  end
end
