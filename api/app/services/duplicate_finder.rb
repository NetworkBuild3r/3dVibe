# Find likely duplicate files in a shared library.
# Exact groups use stored SHA-256. Name+size groups stream-hash only those
# candidates (never load the file into RAM) so we can upgrade or keep a heuristic.
class DuplicateFinder
  def initialize(library)
    @library = library
  end

  def call
    assets = Asset.joins(:vibe_model)
                  .where(vibe_models: { library_id: @library.id })
                  .includes(:vibe_model)
                  .to_a

    exact, claimed = exact_groups(assets)
    heuristic = heuristic_groups(assets, claimed)
    confirm_heuristic!(heuristic)

    groups = (exact + heuristic).sort_by { |group| [-group[:assets].size, group[:reason], group[:id]] }
    groups.each { |group| group.delete(:_records) }
    {
      library_id: @library.id,
      group_count: groups.size,
      groups: groups
    }
  end

  private

  def exact_groups(assets)
    claimed = Set.new
    groups = assets
      .select { |asset| asset.content_digest.present? }
      .group_by(&:content_digest)
      .filter_map do |digest, members|
        next if members.size < 2

        members.each { |asset| claimed << asset.id }
        serialize_group(
          id: "digest:#{digest}",
          reason: "content_hash",
          confidence: "exact",
          digest: digest,
          members: members
        )
      end
    [groups, claimed]
  end

  def heuristic_groups(assets, claimed)
    assets
      .group_by { |asset| [asset.filename.to_s.downcase, asset.byte_size.to_i] }
      .filter_map do |(filename, byte_size), members|
        leftover = members.reject { |asset| claimed.include?(asset.id) }
        next if leftover.size < 2

        serialize_group(
          id: "name-size:#{filename}:#{byte_size}",
          reason: "name_size",
          confidence: "likely",
          digest: nil,
          members: leftover
        )
      end
  end

  def confirm_heuristic!(groups)
    groups.each do |group|
      members = group.delete(:_records) || []
      digests = members.filter_map do |asset|
        digest = asset.content_digest.presence || stream_digest(asset)
        next if digest.blank?

        asset.update_column(:content_digest, digest) if asset.content_digest.blank?
        digest
      end.uniq

      next unless digests.size == 1 && members.size >= 2

      group[:reason] = "content_hash"
      group[:confidence] = "exact"
      group[:digest] = digests.first
      group[:id] = "digest:#{digests.first}"
      group[:assets].each { |row| row[:content_digest] ||= digests.first }
    end
  end

  def stream_digest(asset)
    path = asset.absolute_path
    return unless File.file?(path)

    Digest::SHA256.file(path).hexdigest
  rescue Errno::ENOENT, Errno::EACCES, Errno::ESTALE
    nil
  end

  def serialize_group(id:, reason:, confidence:, digest:, members:)
    sample = members.first
    {
      id: id,
      reason: reason,
      confidence: confidence,
      digest: digest,
      filename: sample.filename,
      byte_size: sample.byte_size,
      assets: members.sort_by { |asset| [asset.vibe_model.title, asset.relative_path, asset.id] }.map { |asset| serialize_asset(asset) },
      _records: members
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
      model_id: asset.vibe_model_id,
      model_title: asset.vibe_model.title,
      folder_name: asset.vibe_model.folder_name
    }
  end
end
