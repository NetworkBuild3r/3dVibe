# Single-id Meili upsert. Hot paths (scan, cover write-back, curation, creator)
# go through SearchIndex.enqueue → BulkIndexVibeModelsJob so this is not
# enqueued once per model during a burst.
class IndexVibeModelJob < ApplicationJob
  queue_as :search

  def perform(model_id)
    model = VibeModel.includes(:tags, :library, :uploaded_by, :creator, assets: :archive_members).find_by(id: model_id)
    return unless model

    SearchIndex.new.upsert(model)
  end
end
