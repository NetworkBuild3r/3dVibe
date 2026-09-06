class ReindexSearchJob < ApplicationJob
  queue_as :search

  def perform(library_id = nil)
    scope = library_id.present? ? VibeModel.where(library_id: library_id) : VibeModel.all
    SearchIndex.new.reindex_all!(scope)
  end
end
