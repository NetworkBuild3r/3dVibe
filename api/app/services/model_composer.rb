# Merge selected models or files into one first-level folder, and split them
# back out. NFS is truth: files are moved with FileUtils.mv (never loaded).
# Destinations stay inside LibraryPathJail.
class ModelComposer
  JUNK_NAMES = %w[.DS_Store Thumbs.db].freeze

  def initialize(library, performed_by:)
    @library = library
    @user = performed_by
    @jail = LibraryPathJail.new(library.root_path)
  end

  def merge!(source_ids: [], asset_ids: [], target_id: nil, title: nil, folder_name: nil)
    source_ids = Array(source_ids).map(&:presence).compact
    asset_ids = Array(asset_ids).map(&:presence).compact
    raise ArgumentError, "select models or files to merge" if source_ids.empty? && asset_ids.empty?

    target = resolve_or_create_target!(target_id, title, folder_name)
    parts = []
    touched = [target.folder_name]

    if source_ids.any?
      sources = @library.vibe_models.where(id: source_ids)
      raise ArgumentError, "source models not found" if sources.size != source_ids.map(&:to_i).uniq.size

      sources.each do |source|
        next if source.id == target.id

        parts << merge_model!(source, target)
        touched << source.folder_name
      end
    end

    if asset_ids.any?
      assets = Asset.joins(:vibe_model).where(vibe_models: { library_id: @library.id }, id: asset_ids)
      raise ArgumentError, "assets not found" if assets.size != asset_ids.map(&:to_i).uniq.size

      assets.each do |asset|
        next if asset.vibe_model_id == target.id

        parts << merge_asset!(asset, target)
        touched << asset.vibe_model.folder_name
      end
    end

    raise ArgumentError, "nothing to merge" if parts.empty?

    record = ModelMerge.create!(
      library: @library,
      target_vibe_model: target,
      performed_by: @user,
      kind: source_ids.any? ? ModelMerge::KINDS.first : "assets",
      parts: parts
    )

    rescan!(touched)
    if title.present?
      record.target_vibe_model.reload.update!(title: title)
    end
    record.reload
    record
  end

  def split!(model, merge_id: nil)
    record = if merge_id.present?
      model.model_merges.find(merge_id)
    else
      model.model_merges.active.recent.first
    end
    raise ArgumentError, "no merge to split" unless record
    raise ArgumentError, "already split" if record.split?

    restored = []
    touched = [record.target_vibe_model.folder_name]

    record.parts.each do |part|
      restored << restore_part!(part, record.target_vibe_model)
      touched << restored.last["folder_name"]
    end

    record.update!(split_at: Time.current, result: { restored: restored })
    rescan!(touched)
    record.reload
  end

  private

  def resolve_or_create_target!(target_id, title, folder_name)
    if target_id.present?
      return @library.vibe_models.find(target_id)
    end

    name = folder_name.presence || slug_folder(title.presence || "merged")
    name = unique_model_folder(name)
    dir = @jail.folder_path(name)
    FileUtils.mkdir_p(dir) unless dir.exist?

    @library.vibe_models.create!(
      folder_name: name,
      title: title.presence || humanize(name),
      uploaded_by: @user
    )
  end

  def merge_model!(source, target)
    source_dir = @jail.folder_path(source.folder_name)
    raise ArgumentError, "source folder missing" unless source_dir.directory?

    prefix = prefix_for(target.folder_name, source.folder_name)
    moved = move_tree!(source_dir, target.folder_name, prefix)
    emptied = remove_empty_tree!(source_dir)
    snapshot = {
      "kind" => "model",
      "source_id" => source.id,
      "folder_name" => source.folder_name,
      "title" => source.title,
      "nested_prefix" => prefix,
      "files" => moved
    }
    if emptied
      source.destroy!
      @library.scan_cursors.where(path_prefix: snapshot["folder_name"]).delete_all
    end
    snapshot
  end

  def merge_asset!(asset, target)
    source_model = asset.vibe_model
    source = @jail.join(source_model.folder_name, asset.relative_path)
    raise ArgumentError, "source file missing" unless source.file?

    prefix = prefix_for(target.folder_name, source_model.folder_name)
    dest_rel = "#{prefix}/#{asset.relative_path}"
    dest = @jail.join(target.folder_name, dest_rel)
    FileUtils.mkdir_p(dest.dirname)
    FileUtils.mv(source.to_s, dest.to_s)

    {
      "kind" => "asset",
      "asset_id" => asset.id,
      "source_id" => source_model.id,
      "folder_name" => source_model.folder_name,
      "title" => source_model.title,
      "nested_prefix" => prefix,
      "source_relative_path" => asset.relative_path,
      "files" => [dest_rel]
    }
  end

  def restore_part!(part, target)
    preferred = part["folder_name"].presence || slug_folder(part["title"].presence || "restored")
    folder = if preferred && (@library.vibe_models.exists?(folder_name: preferred) || @jail.folder_path(preferred).exist?)
      @jail.normalize_model_folder(preferred)
    else
      unique_model_folder(preferred)
    end
    FileUtils.mkdir_p(@jail.folder_path(folder))
    prefix = part["nested_prefix"].to_s
    restored_files = []

    Array(part["files"]).each do |rel|
      src = @jail.join(target.folder_name, rel)
      next unless src.file?

      dest_rel = if prefix.present? && rel.start_with?("#{prefix}/")
        rel.delete_prefix("#{prefix}/")
      else
        part["source_relative_path"].presence || File.basename(rel)
      end
      dest = @jail.join(folder, dest_rel)
      FileUtils.mkdir_p(dest.dirname)
      FileUtils.mv(src.to_s, dest.to_s)
      restored_files << dest_rel
    end

    {
      "folder_name" => folder,
      "title" => part["title"],
      "files" => restored_files
    }
  end

  def move_tree!(source_dir, target_folder, prefix)
    moved = []
    each_regular_file(source_dir) do |path, rel|
      dest = @jail.join(target_folder, "#{prefix}/#{rel}")
      FileUtils.mkdir_p(dest.dirname)
      FileUtils.mv(path.to_s, dest.to_s)
      moved << "#{prefix}/#{rel}"
    end
    moved
  end

  def each_regular_file(dir)
    Pathname.new(dir).find do |path|
      next unless path.file?
      next if JUNK_NAMES.include?(path.basename.to_s)

      yield path, path.relative_path_from(dir).to_s
    end
  end

  def prefix_for(target_folder, desired)
    @prefixes ||= {}
    key = [target_folder, desired]
    @prefixes[key] ||= unique_nested_prefix(target_folder, desired)
  end

  def unique_nested_prefix(target_folder, desired)
    base = begin
      @jail.normalize_folder(desired)
    rescue ArgumentError
      "part"
    end
    candidate = base
    n = 2
    loop do
      path = @jail.join(target_folder, candidate)
      return candidate unless path.exist?

      candidate = "#{base}-#{n}"
      n += 1
    end
  end

  def unique_model_folder(desired)
    base = begin
      @jail.normalize_model_folder(desired.to_s)
    rescue ArgumentError
      slug_folder(desired)
    end
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
    base = "merged" if base.blank?
    base
  end

  def humanize(folder_name)
    folder_name.to_s.tr("_-", " ").squeeze(" ").strip.split.map(&:capitalize).join(" ")
  end

  def remove_empty_tree!(dir)
    return false unless dir.directory?

    dir.children.each do |child|
      if child.directory?
        remove_empty_tree!(child)
      elsif JUNK_NAMES.include?(child.basename.to_s)
        child.unlink
      end
    end
    return false unless dir.empty?

    dir.rmdir
    true
  rescue Errno::ENOTEMPTY, Errno::ENOENT
    false
  end

  def rescan!(prefixes)
    prefixes.uniq.compact.each do |prefix|
      next if prefix.blank?

      LibraryScanner.new(@library, uploaded_by: @user, trigger: ScanRun::TRIGGER_CURATION).scan!(path_prefix: prefix)
    rescue ArgumentError
      next
    end
  end
end
