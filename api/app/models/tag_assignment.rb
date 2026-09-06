class TagAssignment < ApplicationRecord
  belongs_to :tag
  belongs_to :taggable, polymorphic: true

  validates :tag_id, uniqueness: { scope: %i[taggable_type taggable_id] }

  after_commit :enqueue_taggable_search_index

  private

  def enqueue_taggable_search_index
    SearchIndex.enqueue(taggable) if taggable.is_a?(VibeModel)
  end
end

