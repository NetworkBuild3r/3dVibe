class RemoveVibeModelIndexJob < ApplicationJob
  queue_as :search

  def perform(model_id)
    SearchIndex.new.remove(model_id)
  end
end
