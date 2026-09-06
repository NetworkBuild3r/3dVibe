# HITL extract of selected archive members into a first-level model folder.
# Streams one member at a time (ArchiveMemberStreamer) into a path-jailed
# destination file. Never loads the parent archive into RAM, never rewrites
# or deletes the source pack, and never silent-deletes NFS files.
class ArchiveMemberExtractor
  Result = Struct.new(:model, :assets, :extracted, :merge, keyword_init: true)

  def initialize(library, performed_by:)
    @library = library
    @user = performed_by
    @jail = LibraryPathJail.new(library.root_path)
  end

  def extract!(archive_member_ids:, target_id: nil, title: nil, folder_name: nil)
    members = load_members!(archive_member_ids)
    target = resolve_or_create_target!(target_id, title, folder_name)
    written = members.map { |member| extract_one!(member, target) }

    rescan!(target.folder_name)
    target.reload

    assets = written.map { |row| target.assets.find_by!(relative_path: row[:relative_path]) }
    extracted = written.zip(assets).map { |row, asset| extracted_row(row, asset, target) }

    Result.new(model: target, assets: assets, extracted: extracted, merge: nil)
  end

  def extract_and_merge!(archive_member_ids:, source_ids: [], asset_ids: [], target_id: nil, title: nil, folder_name: nil)
    result = extract!(
      archive_member_ids: archive_member_ids,
      target_id: target_id,
      title: title,
      folder_name: folder_name
    )

    extra_sources = Array(source_ids).map(&:presence).compact.reject { |id| id.to_i == result.model.id }
    extra_assets = Array(asset_ids).map(&:presence).compact.filter_map do |id|
      asset = Asset.joins(:vibe_model).find_by!(vibe_models: { library_id: @library.id }, id: id)
      next if asset.vibe_model_id == result.model.id

      asset.id
    end

    if extra_sources.any? || extra_assets.any?
      result.merge = ModelComposer.new(@library, performed_by: @user).merge!(
        source_ids: extra_sources,
        asset_ids: extra_assets,
        target_id: result.model.id,
        title: title
      )
      result.model = result.merge.target_vibe_model.reload
      result.assets = result.extracted.map { |row| result.model.assets.find_by!(id: row[:asset_id]) }
    elsif title.present?
      result.model.update!(title: title)
    end

    result
  end

  private

  def load_members!(archive_member_ids)
    ids = Array(archive_member_ids).map(&:presence).compact
    raise ArgumentError, "select archive members to extract" if ids.empty?

    members = ArchiveMember.joins(asset: :vibe_model)
                           .where(vibe_models: { library_id: @library.id }, id: ids)
                           .includes(asset: :vibe_model)
                           .to_a
    raise ArgumentError, "archive members not found" if members.size != ids.map(&:to_i).uniq.size

    members.each do |member|
      raise ArgumentError, "cannot extract a directory" if member.directory?
      raise ArgumentError, "cannot extract a placeholder listing" if member.placeholder?
      raise ArgumentError, "member is not streamable" unless member.streamable?
    end
    members
  end

  def extract_one!(member, target)
    relative = unique_relative(target.folder_name, safe_basename(member))
    dest = @jail.join(target.folder_name, relative)
    FileUtils.mkdir_p(dest.dirname)

    streamer = ArchiveMemberStreamer.for_member(member)
    begin
      File.open(dest, "wb") do |io|
        streamer.each { |chunk| io.write(chunk) }
      end
      @jail.assert_realpath_inside!(dest)
    rescue StandardError
      FileUtils.rm_f(dest.to_s)
      raise
    end

    {
      archive_member_id: member.id,
      relative_path: relative,
      archive_path: member.archive_path
    }
  end

  def extracted_row(row, asset, target)
    {
      archive_member_id: row[:archive_member_id],
      asset_id: asset.id,
      model_id: target.id,
      relative_path: asset.relative_path,
      filename: asset.filename,
      mergeable: true,
      archive_path: row[:archive_path]
    }
  end

  def safe_basename(member)
    name = member.basename.presence || ArchiveMember.basename_of(member.internal_path)
    @jail.normalize_relative(name)
  end

  def unique_relative(target_folder, desired)
    base = @jail.normalize_relative(desired)
    ext = File.extname(base)
    stem = base.delete_suffix(ext)
    candidate = base
    n = 2
    loop do
      path = @jail.join(target_folder, candidate)
      return candidate unless path.exist?

      candidate = "#{stem}-#{n}#{ext}"
      n += 1
    end
  end

  def resolve_or_create_target!(target_id, title, folder_name)
    if target_id.present?
      return @library.vibe_models.find(target_id)
    end

    name = if folder_name.present?
      @jail.normalize_model_folder(folder_name)
    else
      slug_folder(title.presence || "extracted")
    end
    name = unique_model_folder(name)
    dir = @jail.folder_path(name)
    FileUtils.mkdir_p(dir) unless dir.exist?

    @library.vibe_models.create!(
      folder_name: name,
      title: title.presence || humanize(name),
      uploaded_by: @user
    )
  end

  def unique_model_folder(desired)
    base = @jail.normalize_model_folder(desired.to_s)
    name = base
    n = 2
    while @library.vibe_models.exists?(folder_name: name) || @jail.folder_path(name).exist?
      name = "#{base}-#{n}"
      n += 1
    end
    name
  end

  def slug_folder(title)
    base = title.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
    base = "extracted" if base.blank?
    base
  end

  def humanize(folder_name)
    folder_name.to_s.tr("_-", " ").squeeze(" ").strip.split.map(&:capitalize).join(" ")
  end

  def rescan!(prefix)
    return if prefix.blank?

    LibraryScanner.new(@library, uploaded_by: @user, trigger: ScanRun::TRIGGER_CURATION)
                  .scan!(path_prefix: prefix)
  end
end
