# Cluster likely duplicate files in a shared library.
# Exact groups use stored SHA-256. Geometry groups use assets.geometry_digest
# (written by Rendering). Name+size leftovers are a heuristic.
# Size-prefilter + streamed hashing (never slurp archives). Path-jailed.
class DuplicateFinder
  Cluster = Struct.new(:reason, :confidence, :digest, :assets, keyword_init: true)

  def initialize(library, budget: nil)
    @library = library
    @budget = budget
    @hashed = 0
    @budget_exhausted = false
  end

  attr_reader :hashed, :budget_exhausted
  alias budget_exhausted? budget_exhausted

  def clusters
    @clusters ||= compute_clusters
  end

  def call
    groups = clusters.map { |cluster| serialize_group(cluster) }
    groups.sort_by! { |group| [-group[:assets].size, group[:reason], group[:id].to_s] }
    {
      library_id: @library.id,
      group_count: groups.size,
      groups: groups
    }
  end

  def mesh_missing_geometry
    load_assets.select { |asset| asset.mesh? && asset.geometry_digest.blank? }
  end

  private

  def compute_clusters
    assets = load_assets
    fill_missing_content_digests!(assets)

    exact, claimed = exact_groups(assets)
    geometry, claimed = geometry_groups(assets, claimed)
    heuristic = heuristic_groups(assets, claimed)
    exact + geometry + heuristic
  end

  def load_assets
    Asset.joins(:vibe_model)
         .where(vibe_models: { library_id: @library.id })
         .includes(vibe_model: :library)
         .to_a
  end

  # Only stream-hash files that share a byte size with another asset.
  # Unique-sized files cannot be exact or name+size hits. Geometry near-dups
  # are grouped later from persisted geometry_digest (any size).
  def fill_missing_content_digests!(assets)
    candidate_ids = size_prefilter_ids(assets)
    assets.each do |asset|
      next unless candidate_ids.include?(asset.id)
      next if asset.content_digest.present?

      if @budget&.exhausted?
        @budget_exhausted = true
        break
      end

      digest = stream_digest(asset)
      @budget&.see_file!
      @hashed += 1
      next if digest.blank?

      asset.update_column(:content_digest, digest)
    end
  end

  def size_prefilter_ids(assets)
    ids = Set.new
    assets.group_by { |asset| asset.byte_size.to_i }.each_value do |members|
      next if members.size < 2

      members.each { |asset| ids << asset.id }
    end
    ids
  end

  def exact_groups(assets)
    claimed = Set.new
    groups = assets
      .select { |asset| asset.content_digest.present? }
      .group_by(&:content_digest)
      .filter_map do |digest, members|
        next if members.size < 2

        members.each { |asset| claimed << asset.id }
        Cluster.new(
          reason: DuplicateGroup::REASON_CONTENT_HASH,
          confidence: DuplicateGroup::CONFIDENCE_EXACT,
          digest: digest,
          assets: members
        )
      end
    [groups, claimed]
  end

  def geometry_groups(assets, claimed)
    groups = assets
      .reject { |asset| claimed.include?(asset.id) }
      .select { |asset| asset.geometry_digest.present? }
      .group_by(&:geometry_digest)
      .filter_map do |digest, members|
        next if members.size < 2

        members.each { |asset| claimed << asset.id }
        Cluster.new(
          reason: DuplicateGroup::REASON_GEOMETRY,
          confidence: DuplicateGroup::CONFIDENCE_GEOMETRY,
          digest: digest,
          assets: members
        )
      end
    [groups, claimed]
  end

  def heuristic_groups(assets, claimed)
    assets
      .group_by { |asset| [asset.filename.to_s.downcase, asset.byte_size.to_i] }
      .filter_map do |(_filename, _byte_size), members|
        leftover = members.reject { |asset| claimed.include?(asset.id) }
        next if leftover.size < 2

        Cluster.new(
          reason: DuplicateGroup::REASON_NAME_SIZE,
          confidence: DuplicateGroup::CONFIDENCE_LIKELY,
          digest: nil,
          assets: leftover
        )
      end
  end

  def stream_digest(asset)
    path = jailed_file(asset)
    return unless path

    Digest::SHA256.file(path.to_s).hexdigest
  rescue Errno::ENOENT, Errno::EACCES, Errno::ESTALE, ArgumentError
    nil
  end

  def jailed_file(asset)
    model = asset.vibe_model
    LibraryPathJail.new(model.library.root_path).resolve_file(model.folder_name, asset.relative_path)
  rescue ArgumentError
    nil
  end

  def serialize_group(cluster)
    sample = cluster.assets.min_by { |asset| [asset.vibe_model.title, asset.relative_path, asset.id] }
    {
      id: cluster.digest.present? ? "#{cluster.reason}:#{cluster.digest}" : "name-size:#{sample.filename.to_s.downcase}:#{sample.byte_size.to_i}",
      reason: cluster.reason,
      confidence: cluster.confidence,
      digest: cluster.digest,
      filename: sample.filename,
      byte_size: sample.byte_size,
      assets: cluster.assets.sort_by { |asset| [asset.vibe_model.title, asset.relative_path, asset.id] }.map { |asset| serialize_asset(asset) }
    }
  end

  def serialize_asset(asset)
    {
      id: asset.id,
      filename: asset.filename,
      relative_path: asset.relative_path,
      kind: asset.kind,
      byte_size: asset.byte_size,
      content_digest: asset.content_digest,
      geometry_digest: asset.geometry_digest,
      model_id: asset.vibe_model_id,
      model_title: asset.vibe_model.title,
      folder_name: asset.vibe_model.folder_name
    }
  end
end
