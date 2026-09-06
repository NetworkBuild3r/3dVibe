# Builds and maintains the Meilisearch vibe_models index.
# No-ops when Meili is not configured or is unreachable.
# Enqueue is debounced: unique model ids flush through BulkIndexVibeModelsJob
# so scan / cover / curation / creator spikes cannot melt Sidekiq or Meili.
class SearchIndex
  DEFAULT_DEBOUNCE_SECONDS = 2.0
  DEFAULT_BATCH_SIZE = 100

  def initialize(client: MeilisearchClient.new)
    @client = client
  end

  def self.debounce_seconds
    [[ENV.fetch("VIBE_SEARCH_INDEX_DEBOUNCE", DEFAULT_DEBOUNCE_SECONDS).to_f, 0].max, 30].min
  end

  def self.batch_size
    [[ENV.fetch("VIBE_SEARCH_INDEX_BATCH", DEFAULT_BATCH_SIZE).to_i, 1].max, 500].min
  end

  def self.enqueue(model)
    return unless model

    enqueue_ids([model.respond_to?(:id) ? model.id : model])
  end

  def self.enqueue_ids(ids)
    return unless MeilisearchClient.configured?

    SearchIndexBuffer.add_ids(ids)
  end

  def self.enqueue_remove(model_id)
    return if model_id.blank?
    return unless MeilisearchClient.configured?

    RemoveVibeModelIndexJob.perform_later(model_id)
  end

  def upsert(model)
    upsert_many([model.id])
  end

  def upsert_many(model_ids)
    ids = Array(model_ids).compact
    return :skipped if ids.empty?
    return :skipped unless @client.configured?
    return :unavailable unless ready?

    count = 0
    VibeModel.includes(:tags, :library, :uploaded_by, :creator, assets: :archive_members)
             .where(id: ids)
             .find_in_batches(batch_size: self.class.batch_size) do |batch|
      @client.upsert_documents(batch.map { |model| document_for(model) })
      count += batch.size
    end
    Rails.logger.info("[SearchIndex] upserted #{count} models") if count > 1
    count.positive? ? :ok : :empty
  rescue MeilisearchClient::Error => e
    Rails.logger.warn("[SearchIndex] upsert failed models=#{ids.join(',')}: #{e.message}")
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
    scope.includes(:tags, :library, :uploaded_by, :creator, assets: :archive_members).find_in_batches(batch_size: self.class.batch_size) do |batch|
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
      kinds: assets.map(&:kind).uniq,
      creator_slug: model.creator&.slug,
      creator: model.creator&.slug,
      creator_name: model.creator&.name,
      cover_status: model.cover_status,
      has_cover: model.has_cover?
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
