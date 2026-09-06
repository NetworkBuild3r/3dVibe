class ArchiveTree
  def initialize(scope)
    @scope = scope
  end

  def children(prefix:, limit:, offset:)
    prefix = ArchiveMember.normalize_prefix(prefix)
    rel = @scope.where(parent_path: prefix).order(directory: :desc, basename: :asc, id: :asc)
    total = rel.count
    nodes = rel.offset(offset).limit(limit).to_a
    [nodes, total, child_counts(nodes)]
  end

  def search(query:, limit:, offset:)
    pattern = "%#{ArchiveMember.sanitize_sql_like(query.to_s)}%"
    rel = @scope.where(directory: false)
                .where("archive_members.internal_path ILIKE :q OR archive_members.basename ILIKE :q", q: pattern)
                .where.not(internal_path: ArchiveMember::PLACEHOLDER_PATH)
                .order(:internal_path, :id)
    total = rel.count
    [rel.offset(offset).limit(limit).to_a, total]
  end

  def flat(limit:, offset:)
    rel = @scope.order(:internal_path, :id)
    [rel.offset(offset).limit(limit).to_a, rel.count]
  end

  private

  def child_counts(nodes)
    prefixes = nodes.select(&:directory?).map(&:internal_path)
    return {} if prefixes.empty?

    @scope.where(parent_path: prefixes).group(:parent_path).count
  end
end
