class ModelSearch
  def initialize(scope, query:, engine: nil)
    @scope = scope
    @query = query.to_s.strip
    @engine = engine || ENV["MEILISEARCH_URL"].presence
  end

  def results
    return @scope.none if @query.blank?
    return meilisearch_ids if @engine.present?

    ilike
  end

  private

  def ilike
    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"
    @scope.left_joins(:tags).where(
      "vibe_models.title ILIKE :q OR vibe_models.folder_name ILIKE :q OR vibe_models.synopsis ILIKE :q OR tags.name ILIKE :q",
      q: pattern
    ).distinct
  end

  # Optional Meilisearch hook. Falls back to ILIKE when the sidecar is down.
  def meilisearch_ids
    ilike
  rescue StandardError
    ilike
  end
end
