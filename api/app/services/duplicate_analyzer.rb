# Persist DuplicateFinder clusters. NFS is never deleted here — DB is an
# index only. Terminal HITL decisions (kept / dismissed / merged) stay put.
#
# Rematch rules:
# - Terminal groups are left alone. If they still match a current cluster
#   (same reason+digest, or same name+size, and at least two current members
#   overlap), those assets are reserved and will not open a new group.
# - Only `open` groups are refreshed (members replaced) or created.
# - Open groups that no longer match a current cluster are destroyed.
#   Their review rows go with them (open groups have no terminal decision).
class DuplicateAnalyzer
  def initialize(library, budget: DuplicateBudget.from_env)
    @library = library
    @budget = budget
  end

  def call
    finder = DuplicateFinder.new(@library, budget: @budget)
    persist!(finder.clusters)
    enqueue_geometry_jobs(finder.mesh_missing_geometry)
    {
      library_id: @library.id,
      group_count: @library.duplicate_groups.count,
      open_count: @library.duplicate_groups.open.count,
      hashed: finder.hashed,
      budget_exhausted: finder.budget_exhausted?,
      budget_reason: @budget&.reason
    }
  end

  private

  def persist!(clusters)
    reserved = reserve_terminal_assets(clusters)
    touched = []

    clusters.each do |cluster|
      members = cluster.assets.reject { |asset| reserved.include?(asset.id) }
      next if members.size < 2

      group = find_open_group(cluster) || @library.duplicate_groups.build
      group.assign_attributes(
        reason: cluster.reason,
        confidence: cluster.confidence,
        digest: cluster.digest,
        status: DuplicateGroup::OPEN
      )
      group.save!
      replace_members!(group, members)
      touched << group.id
    end

    stale = @library.duplicate_groups.open.where.not(id: touched)
    stale.find_each(&:destroy!)
  end

  def reserve_terminal_assets(clusters)
    by_key = clusters.index_by { |cluster| cluster_key(cluster) }
    reserved = Set.new
    @library.duplicate_groups.terminal.includes(duplicate_group_members: :asset).find_each do |group|
      current = by_key[group_key(group)]
      next unless current

      member_ids = group.duplicate_group_members.map(&:asset_id).to_set
      overlap = current.assets.map(&:id).select { |id| member_ids.include?(id) }
      next if overlap.size < 2

      reserved.merge(member_ids)
    end
    reserved
  end

  def find_open_group(cluster)
    scope = @library.duplicate_groups.open.where(reason: cluster.reason)
    if cluster.digest.present?
      return scope.find_by(digest: cluster.digest)
    end

    sample = cluster.assets.min_by { |asset| [asset.filename.to_s.downcase, asset.byte_size.to_i, asset.id] }
    scope.joins(duplicate_group_members: :asset)
         .where("LOWER(assets.filename) = ? AND assets.byte_size = ?", sample.filename.to_s.downcase, sample.byte_size.to_i)
         .distinct
         .first
  end

  def replace_members!(group, assets)
    keep_ids = assets.map(&:id)
    group.duplicate_group_members.where.not(asset_id: keep_ids).delete_all
    assets.each do |asset|
      member = group.duplicate_group_members.find_or_initialize_by(asset_id: asset.id)
      member.vibe_model_id = asset.vibe_model_id
      member.save!
    end
  end

  def enqueue_geometry_jobs(assets)
    assets.each { |asset| ComputeGeometryDigestJob.perform_later(asset.id) }
  end

  def cluster_key(cluster)
    DuplicateGroup.match_key(reason: cluster.reason, digest: cluster.digest, assets: cluster.assets)
  end

  def group_key(group)
    DuplicateGroup.match_key(reason: group.reason, digest: group.digest, assets: group.assets.to_a)
  end
end
