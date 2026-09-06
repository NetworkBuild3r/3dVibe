class ModelSearch
  Result = Struct.new(
    :models, :engine, :fallback, :offset, :limit, :estimated_total, :next_offset, :facets, :query, :capped,
    keyword_init: true
  )

  FACET_KEYS = %w[tags has_preview creator_slug cover_status has_cover].freeze
  DEFAULT_FALLBACK_CAP = 250
  DEFAULT_FALLBACK_JOIN_SCAN = 500

  def self.fallback_cap
    [[ENV.fetch("VIBE_SEARCH_FALLBACK_CAP", DEFAULT_FALLBACK_CAP).to_i, 1].max, 1_000].min
  end

  def self.fallback_join_scan
    [[ENV.fetch("VIBE_SEARCH_FALLBACK_JOIN_SCAN", DEFAULT_FALLBACK_JOIN_SCAN).to_i, 50].max, 2_000].min
  end

  def self.trgm_available?
    return @trgm_available unless @trgm_available.nil?

    @trgm_available = ActiveRecord::Base.connection.extension_enabled?("pg_trgm")
  rescue StandardError
    @trgm_available = false
  end

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
      facets: FACET_KEYS
    )
    ids = Array(raw["hits"]).map { |hit| hit["id"].to_i }
    models = hydrate(ids)
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
      query: @query,
      capped: false
    )
  rescue MeilisearchClient::Error, Timeout::Error, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError => e
    Rails.logger.warn("[ModelSearch] Meilisearch unavailable, falling back to Postgres: #{e.message}")
    postgres_result(engine: "postgres", fallback: true)
  end

  def postgres_result(engine:, fallback:)
    filtered = ModelCatalogFilters.apply(@scope, @filters)
    if @query.present?
      ids = text_search_ids(filtered)
      capped = ids.size >= self.class.fallback_cap
      total = ids.size
      page_ids = ids.drop(@offset).first(@limit)
      models = hydrate(page_ids)
      facets = postgres_facets(ids)
    else
      capped = false
      total = filtered.except(:select, :order, :includes, :preload, :eager_load).reselect("vibe_models.id").distinct.count
      models = filtered.includes(:tags, :library, :uploaded_by, :creator, :assets).recent.offset(@offset).limit(@limit).to_a
      facets = postgres_facets(filtered)
    end

    Result.new(
      models: models,
      engine: engine,
      fallback: fallback,
      offset: @offset,
      limit: @limit,
      estimated_total: total,
      next_offset: (@offset + models.size < total) ? @offset + models.size : nil,
      facets: facets,
      query: @query,
      capped: capped
    )
  end

  # Staged ILIKE so a Meili outage does not join assets × archive_members across the catalog.
  # Each source is LIMIT-capped. When pg_trgm is enabled, ILIKE '%q%' can use the GIN indexes.
  def text_search_ids(scope)
    base_ids = scope.except(:select, :order, :includes, :preload, :eager_load, :group, :having).reselect("vibe_models.id")
    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"
    cap = self.class.fallback_cap
    join_scan = self.class.fallback_join_scan
    found = Set.new
    models = VibeModel.where(id: base_ids)

    add_ids(found, cap, models.where(
      "vibe_models.title ILIKE :q OR vibe_models.folder_name ILIKE :q OR vibe_models.synopsis ILIKE :q",
      q: pattern
    ))
    add_ids(found, cap, models.joins(:creator).where("creators.name ILIKE :q OR creators.slug ILIKE :q", q: pattern))
    add_ids(found, cap, models.joins(:uploaded_by).where("users.display_name ILIKE :q", q: pattern))
    add_ids(found, cap, models.joins(:tags).where("tags.name ILIKE :q", q: pattern))

    if found.size < cap
      asset_model_ids = Asset.where(vibe_model_id: base_ids)
                             .where("assets.filename ILIKE :q OR assets.relative_path ILIKE :q", q: pattern)
                             .limit(join_scan)
                             .pluck(:vibe_model_id)
      asset_model_ids.each { |id| found << id if found.size < cap }
    end

    if found.size < cap
      member_model_ids = Asset.joins(:archive_members)
                              .where(vibe_model_id: base_ids)
                              .where(
                                <<~SQL.squish,
                                  archive_members.directory = FALSE
                                  AND archive_members.internal_path <> :placeholder
                                  AND archive_members.internal_path ILIKE :q
                                SQL
                                q: pattern,
                                placeholder: ArchiveMember::PLACEHOLDER_PATH
                              )
                              .limit(join_scan)
                              .pluck(:vibe_model_id)
      member_model_ids.each { |id| found << id if found.size < cap }
    end

    VibeModel.where(id: found.to_a).recent.limit(cap).pluck(:id)
  end

  def add_ids(found, cap, relation)
    return if found.size >= cap

    relation.limit(cap - found.size).pluck(:id).each { |id| found << id }
  end

  def hydrate(ids)
    records = @scope.includes(:tags, :library, :uploaded_by, :creator, :assets).where(id: ids).index_by(&:id)
    ids.filter_map { |id| records[id] }
  end

  def meili_filter
    clauses = []
    ModelCatalogFilters.tag_values(@filters[:tags]).each { |name| clauses << "tags = #{meili_quote(name)}" }
    clauses << "library_id = #{@filters[:library_id].to_i}" if @filters[:library_id].present?
    clauses << "uploaded_by_id = #{@filters[:uploaded_by_id].to_i}" if @filters[:uploaded_by_id].present?
    slug = (@filters[:creator_slug].presence || @filters[:creator].presence).to_s.strip.downcase
    clauses << "creator_slug = #{meili_quote(slug)}" if slug.present?
    status = @filters[:cover_status].to_s.strip.downcase
    clauses << "cover_status = #{meili_quote(status)}" if status.present? && VibeModel::COVER_STATUSES.include?(status)
    case truthy(@filters[:has_cover])
    when true then clauses << "has_cover = true"
    when false then clauses << "has_cover = false"
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
    FACET_KEYS.index_with { |key| hash[key] || {} }
  end

  def postgres_facets(scope_or_ids)
    ids = if scope_or_ids.is_a?(Array)
      scope_or_ids
    else
      scope_or_ids.except(:order, :includes, :preload, :eager_load).reselect("vibe_models.id")
    end
    tag_counts = Tag.joins(:tag_assignments)
                    .where(tag_assignments: { taggable_type: "VibeModel", taggable_id: ids })
                    .group("tags.name")
                    .count
    cover_counts = VibeModel.where(id: ids).group(:cover_status).count
    ready = cover_counts[VibeModel::COVER_READY] || 0
    total = VibeModel.where(id: ids).count
    preview_count = VibeModel.where(id: ids).where(id: ModelCatalogFilters.previewable_model_ids).count
    creator_counts = Creator.joins(:vibe_models).where(vibe_models: { id: ids }).group("creators.slug").count
    {
      "tags" => tag_counts,
      "has_preview" => { "true" => preview_count, "false" => [total - preview_count, 0].max },
      "creator_slug" => creator_counts,
      "cover_status" => cover_counts,
      "has_cover" => { "true" => ready, "false" => [total - ready, 0].max }
    }
  end
end
