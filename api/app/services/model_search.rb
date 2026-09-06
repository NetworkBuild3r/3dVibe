class ModelSearch
  Result = Struct.new(
    :models, :engine, :fallback, :offset, :limit, :estimated_total, :next_offset, :facets, :query,
    keyword_init: true
  )

  def initialize(scope, query:, filters: {}, offset: 0, limit: 24, client: nil)
    @scope = scope
    @query = query.to_s.strip
    @filters = (filters || {}).symbolize_keys
    @offset = [offset.to_i, 0].max
    @limit = [[limit.to_i, 1].max, 60].min
    @client = client || MeilisearchClient.new
  end

  def call
    if @client.configured?
      meilisearch_result
    else
      postgres_result(engine: "postgres", fallback: false)
    end
  end

  def results
    call.models
  end

  private

  def meilisearch_result
    raw = @client.search(
      @query,
      filter: meili_filter,
      offset: @offset,
      limit: @limit,
      facets: %w[tags has_preview creator_slug]
    )
    ids = Array(raw["hits"]).map { |hit| hit["id"].to_i }
    records = @scope.includes(:tags, :library, :uploaded_by, :creator, :assets).where(id: ids).index_by(&:id)
    models = ids.filter_map { |id| records[id] }
    total = (raw["estimatedTotalHits"] || raw["totalHits"] || models.size).to_i
    Result.new(
      models: models,
      engine: "meilisearch",
      fallback: false,
      offset: @offset,
      limit: @limit,
      estimated_total: total,
      next_offset: (@offset + models.size < total) && models.size == @limit ? @offset + models.size : nil,
      facets: normalize_facets(raw["facetDistribution"]),
      query: @query
    )
  rescue MeilisearchClient::Error, Timeout::Error, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError => e
    Rails.logger.warn("[ModelSearch] Meilisearch unavailable, falling back to Postgres: #{e.message}")
    postgres_result(engine: "postgres", fallback: true)
  end

  def postgres_result(engine:, fallback:)
    filtered = apply_postgres_filters(ilike(@scope))
    total = filtered.except(:select, :order, :includes, :preload, :eager_load).reselect("vibe_models.id").distinct.count
    models = filtered.includes(:tags, :library, :uploaded_by, :creator, :assets).recent.offset(@offset).limit(@limit).to_a
    Result.new(
      models: models,
      engine: engine,
      fallback: fallback,
      offset: @offset,
      limit: @limit,
      estimated_total: total,
      next_offset: (@offset + models.size < total) ? @offset + models.size : nil,
      facets: postgres_facets(filtered),
      query: @query
    )
  end

  def ilike(scope)
    return scope if @query.blank?

    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"
    scope.left_joins(:tags, :uploaded_by, :creator, assets: :archive_members).where(
      <<~SQL.squish,
        vibe_models.title ILIKE :q
        OR vibe_models.folder_name ILIKE :q
        OR vibe_models.synopsis ILIKE :q
        OR tags.name ILIKE :q
        OR users.display_name ILIKE :q
        OR creators.name ILIKE :q
        OR creators.slug ILIKE :q
        OR assets.filename ILIKE :q
        OR assets.relative_path ILIKE :q
        OR (
          archive_members.directory = FALSE
          AND archive_members.internal_path <> :placeholder
          AND archive_members.internal_path ILIKE :q
        )
      SQL
      q: pattern,
      placeholder: ArchiveMember::PLACEHOLDER_PATH
    ).distinct
  end

  def apply_postgres_filters(scope)
    tags = Array(@filters[:tags]).map { |name| name.to_s.strip.downcase }.reject(&:blank?)
    if tags.any?
      tags.each do |name|
        scope = scope.where(
          id: TagAssignment.where(taggable_type: "VibeModel").joins(:tag).where(tags: { name: name }).select(:taggable_id)
        )
      end
    end

    scope = scope.where(library_id: @filters[:library_id]) if @filters[:library_id].present?
    scope = scope.where(uploaded_by_id: @filters[:uploaded_by_id]) if @filters[:uploaded_by_id].present?
    if @filters[:creator_slug].present?
      scope = scope.joins(:creator).where(creators: { slug: @filters[:creator_slug].to_s.strip.downcase })
    end

    case truthy(@filters[:has_preview])
    when true
      scope = scope.where(id: previewable_model_ids)
    when false
      scope = scope.where.not(id: previewable_model_ids)
    end

    scope
  end

  def previewable_model_ids
    mesh = Asset.where(kind: Asset::MESH_KINDS).select(:vibe_model_id)
    archive = Asset.joins(:archive_members).where(
      "LOWER(SUBSTRING(archive_members.internal_path FROM '\\.([^.]+)$')) IN (?)",
      %w[stl obj 3mf png jpg jpeg webp txt md]
    ).select(:vibe_model_id)
    VibeModel.where(id: mesh).or(VibeModel.where(id: archive)).select(:id)
  end

  def meili_filter
    clauses = []
    tags = Array(@filters[:tags]).map { |name| name.to_s.strip.downcase }.reject(&:blank?)
    tags.each { |name| clauses << "tags = #{meili_quote(name)}" }
    clauses << "library_id = #{@filters[:library_id].to_i}" if @filters[:library_id].present?
    clauses << "uploaded_by_id = #{@filters[:uploaded_by_id].to_i}" if @filters[:uploaded_by_id].present?
    if @filters[:creator_slug].present?
      clauses << "creator_slug = #{meili_quote(@filters[:creator_slug].to_s.strip.downcase)}"
    end
    case truthy(@filters[:has_preview])
    when true then clauses << "has_preview = true"
    when false then clauses << "has_preview = false"
    end
    clauses.join(" AND ").presence
  end

  def meili_quote(value)
    "\"#{value.to_s.gsub('"', '\\"')}\""
  end

  def truthy(value)
    return if value.nil? || value == ""

    ActiveModel::Type::Boolean.new.cast(value)
  end

  def normalize_facets(distribution)
    hash = (distribution || {}).stringify_keys
    {
      "tags" => (hash["tags"] || {}),
      "has_preview" => (hash["has_preview"] || {}),
      "creator_slug" => (hash["creator_slug"] || {})
    }
  end

  def postgres_facets(scope)
    ids = scope.except(:order, :includes, :preload, :eager_load).reselect("vibe_models.id")
    tag_counts = Tag.joins(:tag_assignments)
                    .where(tag_assignments: { taggable_type: "VibeModel", taggable_id: ids })
                    .group("tags.name")
                    .count
    preview_count = VibeModel.where(id: ids).where(id: previewable_model_ids).count
    total = VibeModel.where(id: ids).count
    creator_counts = Creator.joins(:vibe_models).where(vibe_models: { id: ids }).group("creators.slug").count
    {
      "tags" => tag_counts,
      "has_preview" => { "true" => preview_count, "false" => [total - preview_count, 0].max },
      "creator_slug" => creator_counts
    }
  end
end
