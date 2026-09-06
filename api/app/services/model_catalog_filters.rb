# Structured gallery/search filters shared by GET /models and GET /search.
# Chip filters (creator / tag / cover) hit indexed columns — no archive join.
class ModelCatalogFilters
  def self.apply(scope, filters)
    new(scope, filters).apply
  end

  def self.tag_values(*values)
    Array(values).flatten.compact.map { |name| name.to_s.strip.downcase }.reject(&:blank?)
  end

  def initialize(scope, filters)
    @scope = scope
    @filters = (filters || {}).symbolize_keys
  end

  def apply
    scope = @scope
    ModelCatalogFilters.tag_values(@filters[:tags]).each do |name|
      scope = scope.where(
        id: TagAssignment.where(taggable_type: "VibeModel").joins(:tag).where(tags: { name: name }).select(:taggable_id)
      )
    end

    scope = scope.where(library_id: @filters[:library_id]) if @filters[:library_id].present?
    scope = scope.where(uploaded_by_id: @filters[:uploaded_by_id]) if @filters[:uploaded_by_id].present?

    slug = creator_slug
    if slug.present?
      scope = scope.where(creator_id: Creator.where(slug: slug).select(:id))
    end

    status = @filters[:cover_status].to_s.strip.downcase
    if status.present? && VibeModel::COVER_STATUSES.include?(status)
      scope = scope.where(cover_status: status)
    end

    case truthy(@filters[:has_cover])
    when true
      scope = scope.where(cover_status: VibeModel::COVER_READY)
    when false
      scope = scope.where.not(cover_status: VibeModel::COVER_READY)
    end

    case truthy(@filters[:has_preview])
    when true
      scope = scope.where(id: self.class.previewable_model_ids)
    when false
      scope = scope.where.not(id: self.class.previewable_model_ids)
    end

    scope
  end

  def self.previewable_model_ids
    mesh = Asset.where(kind: Asset::MESH_KINDS).select(:vibe_model_id)
    archive = Asset.joins(:archive_members).where(
      "LOWER(SUBSTRING(archive_members.internal_path FROM '\\.([^.]+)$')) IN (?)",
      %w[stl obj 3mf png jpg jpeg webp txt md]
    ).select(:vibe_model_id)
    VibeModel.where(id: mesh).or(VibeModel.where(id: archive)).select(:id)
  end

  private

  def creator_slug
    (@filters[:creator_slug].presence || @filters[:creator].presence).to_s.strip.downcase.presence
  end

  def truthy(value)
    return if value.nil? || value == ""

    ActiveModel::Type::Boolean.new.cast(value)
  end
end
