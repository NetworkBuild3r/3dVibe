# Persist DuplicateFinder clusters. NFS is never deleted here — DB is an
# index only. Terminal HITL decisions (kept / dismissed / merged) stay put.
#
# Geometry clusters include loose assets and archive members that share a
# geometry_digest (loose↔member↔member). Exact content_hash stays Asset-only.
#
# Rematch rules:
# - Terminal groups are left alone. If they still match a current cluster
#   (same reason+digest, or same name+size, and at least two current members
#   overlap), those members are reserved and will not open a new group.
# - Only `open` groups are refreshed (members replaced) or created.
# - Open groups that no longer match a current cluster are destroyed.
#   Their review rows go with them (open groups have no terminal decision).
class DuplicateAnalyzer
  def initialize(library, budget: DuplicateBudget.from_env)
    @library = library
    @budget = budget
  end

  def call
    fingerprint_pending_meshes!
    finder = DuplicateFinder.new(@library, budget: @budget)
    persist!(finder.clusters)
    enqueue_geometry_jobs(finder.mesh_missing_geometry)
    enqueue_archive_member_geometry_jobs(finder.archive_members_missing_geometry)
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
    reserved_assets, reserved_members = reserve_terminal_members(clusters)
    touched = []

    clusters.each do |cluster|
      assets = cluster.assets.reject { |asset| reserved_assets.include?(asset.id) }
      members = cluster.archive_members.reject { |member| reserved_members.include?(member.id) }
      next if assets.size + members.size < 2

      group = find_open_group(cluster) || @library.duplicate_groups.build
      group.assign_attributes(
        reason: cluster.reason,
        confidence: cluster.confidence,
        digest: cluster.digest,
        status: DuplicateGroup::OPEN
      )
      group.save!
      replace_members!(group, assets: assets, archive_members: members)
      touched << group.id
    end

    stale = @library.duplicate_groups.open.where.not(id: touched)
    stale.find_each(&:destroy!)
  end

  def reserve_terminal_members(clusters)
    by_key = clusters.index_by { |cluster| cluster_key(cluster) }
    reserved_assets = Set.new
    reserved_members = Set.new
    @library.duplicate_groups.terminal.includes(duplicate_group_members: %i[asset archive_member]).find_each do |group|
      current = by_key[group_key(group)]
      next unless current

      group_asset_ids = group.duplicate_group_members.filter_map(&:asset_id).to_set
      group_member_ids = group.duplicate_group_members.filter_map(&:archive_member_id).to_set
      overlap = current.assets.count { |asset| group_asset_ids.include?(asset.id) } +
        current.archive_members.count { |member| group_member_ids.include?(member.id) }
      next if overlap < 2

      reserved_assets.merge(group_asset_ids)
      reserved_members.merge(group_member_ids)
    end
    [reserved_assets, reserved_members]
  end

  def find_open_group(cluster)
    scope = @library.duplicate_groups.open.where(reason: cluster.reason)
    if cluster.digest.present?
      return scope.find_by(digest: cluster.digest)
    end

    sample = cluster.assets.min_by { |asset| [asset.filename.to_s.downcase, asset.byte_size.to_i, asset.id] }
    return if sample.blank?

    scope.joins(duplicate_group_members: :asset)
         .where("LOWER(assets.filename) = ? AND assets.byte_size = ?", sample.filename.to_s.downcase, sample.byte_size.to_i)
         .distinct
         .first
  end

  def replace_members!(group, assets:, archive_members:)
    keep_asset_ids = assets.map(&:id)
    keep_member_ids = archive_members.map(&:id)
    group.duplicate_group_members.find_each do |row|
      keep = if row.asset?
        keep_asset_ids.include?(row.asset_id)
      else
        keep_member_ids.include?(row.archive_member_id)
      end
      row.delete unless keep
    end

    assets.each do |asset|
      member = group.duplicate_group_members.find_or_initialize_by(asset_id: asset.id)
      member.archive_member_id = nil
      member.vibe_model_id = asset.vibe_model_id
      member.save!
    end

    archive_members.each do |archive_member|
      member = group.duplicate_group_members.find_or_initialize_by(archive_member_id: archive_member.id)
      member.asset_id = nil
      member.vibe_model_id = archive_member.asset.vibe_model_id
      member.save!
    end
  end

  def fingerprint_pending_meshes!
    geo = GeometryBudget.from_env
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    processed = 0
    pending_meshes.find_each do |asset|
      break if geo.max_assets.positive? && processed >= geo.max_assets
      break if geo.max_seconds.positive? &&
        (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) >= geo.max_seconds

      digest = GeometryFingerprint.compute(asset)
      GeometryWriteback.apply!(asset_id: asset.id, geometry_digest: digest) if digest.present?
      processed += 1
    end
  end

  def pending_meshes
    Asset.joins(:vibe_model)
         .where(vibe_models: { library_id: @library.id }, kind: GeometryFingerprint::KINDS)
         .where(geometry_digest: [nil, ""])
         .order(:id)
  end

  def enqueue_geometry_jobs(assets)
    assets.each { |asset| ComputeGeometryDigestJob.perform_later(asset.id) }
  end

  def enqueue_archive_member_geometry_jobs(members)
    members.each { |member| ComputeArchiveMemberGeometryDigestJob.perform_later(member.id) }
  end

  def cluster_key(cluster)
    DuplicateGroup.match_key(reason: cluster.reason, digest: cluster.digest, assets: cluster.assets)
  end

  def group_key(group)
    DuplicateGroup.match_key(reason: group.reason, digest: group.digest, assets: group.assets.to_a)
  end
end
