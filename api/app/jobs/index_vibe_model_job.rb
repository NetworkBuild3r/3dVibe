class IndexVibeModelJob < ApplicationJob
  queue_as :search

  def perform(model_id)
    model = VibeModel.includes(:tags, :library, :uploaded_by, :creator, assets: :archive_members).find_by(id: model_id)
    return unless model

    SearchIndex.new.upsert(model)
  end
end
