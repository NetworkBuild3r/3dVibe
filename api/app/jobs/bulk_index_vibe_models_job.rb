# Drains unique model ids buffered by SearchIndex and upserts them in one
# Meili HTTP call (or a few, at VIBE_SEARCH_INDEX_BATCH). Re-schedules when
# more ids arrived during the upsert so scan/cover bursts stay coalesced.
class BulkIndexVibeModelsJob < ApplicationJob
  queue_as :search

  def perform(model_ids = nil)
    SearchIndexBuffer.release_flush!
    ids = Array(model_ids).compact.map { |id| Integer(id) }
    ids = SearchIndexBuffer.drain(SearchIndex.batch_size) if ids.empty?
    SearchIndex.new.upsert_many(ids) if ids.any?
    SearchIndexBuffer.schedule_if_pending!
  end
end
