# Builds and maintains the Meilisearch vibe_models index.
# No-ops when Meili is not configured or is unreachable.
class SearchIndex
  def initialize(client: MeilisearchClient.new)
    @client = client
  end

  def self.enqueue(model)
    return unless model
    return unless MeilisearchClient.configured?

    IndexVibeModelJob.perform_later(model.id)
  end

  def self.enqueue_remove(model_id)
    return if model_id.blank?
    return unless MeilisearchClient.configured?

    RemoveVibeModelIndexJob.perform_later(model_id)
  end

  def upsert(model)
    return :skipped unless @client.configured?
    return :unavailable unless ready?

    @client.upsert_documents([document_for(model)])
    :ok
  rescue MeilisearchClient::Error => e
    Rails.logger.warn("[SearchIndex] upsert failed model=#{model.id}: #{e.message}")
    :failed
  end

  def remove(model_id)
    return :skipped unless @client.configured?
    return :unavailable unless ready?

    @client.delete_document(model_id)
    :ok
  rescue MeilisearchClient::Error => e
    Rails.logger.warn("[SearchIndex] remove failed model=#{model_id}: #{e.message}")
    :failed
  end

  def reindex_all!(scope = VibeModel.all)
    return :skipped unless @client.configured?
    return :unavailable unless ready?

    @client.ensure_index!
    count = 0
    scope.includes(:tags, :library, :uploaded_by, assets: :archive_members).find_in_batches(batch_size: 100) do |batch|
      @client.upsert_documents(batch.map { |model| document_for(model) })
      count += batch.size
    end
    Rails.logger.info("[SearchIndex] reindexed #{count} models")
    count
  rescue MeilisearchClient::Error => e
    Rails.logger.warn("[SearchIndex] reindex failed: #{e.message}")
    :failed
  end

  def document_for(model)
    assets = model.assets.to_a
    members = assets.flat_map(&:archive_members).reject { |member| member.directory? || member.placeholder? }
    {
      id: model.id,
      name: model.title,
      title: model.title,
      folder_name: model.folder_name,
      path: model.folder_name,
      synopsis: model.synopsis.to_s,
      tags: model.tags.map(&:name),
      filenames: assets.map(&:filename),
      asset_paths: assets.map(&:relative_path),
      archive_paths: members.map(&:internal_path),
      uploader: model.uploaded_by&.display_name,
      uploaded_by_id: model.uploaded_by_id,
      updated_at: model.updated_at&.to_i,
      has_preview: model.previewable?,
      library_id: model.library_id,
      kinds: assets.map(&:kind).uniq
    }
  end

  private

  def ready?
    return @ready unless @ready.nil?

    @ready =
      if @client.available?
        @client.ensure_index!
        true
      else
        false
      end
  rescue MeilisearchClient::Error => e
    Rails.logger.warn("[SearchIndex] ensure_index failed: #{e.message}")
    @ready = false
  end
end
