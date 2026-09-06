class LibraryScanner
  SKIP_NAMES = %w[. .. .DS_Store Thumbs.db].freeze

  def initialize(library, uploaded_by: nil)
    @library = library
    @uploaded_by = uploaded_by
  end

  def scan!(path_prefix: nil)
    root = Pathname.new(@library.root_path)
    raise ArgumentError, "Library root is not a directory: #{root}" unless root.directory?

    children = targeted_children(root, path_prefix)
    existing_folders = []

    children.sort.each do |child|
      next unless child.directory?
      next if hidden_name?(child.basename.to_s)

      folder_name = child.basename.to_s
      existing_folders << folder_name
      fingerprint = folder_fingerprint(child)
      cursor = @library.scan_cursors.find_or_initialize_by(path_prefix: folder_name)

      next unless cursor.stale?(mtime: fingerprint[:mtime], byte_size: fingerprint[:byte_size])

      index_folder(child, folder_name, fingerprint)
      cursor.remember!(mtime: fingerprint[:mtime], byte_size: fingerprint[:byte_size])
    end

    unless path_prefix.present?
      stale = @library.vibe_models.where.not(folder_name: existing_folders)
      stale.find_each(&:destroy)
      @library.scan_cursors.where.not(path_prefix: existing_folders).delete_all
    end

    @library
  end

  private

  def targeted_children(root, path_prefix)
    return root.children unless path_prefix.present?

    folder = LibraryPathJail.new(root).normalize_folder(path_prefix)
    target = root.join(folder)
    target.directory? ? [target] : []
  end

  def hidden_name?(name)
    name.start_with?(".") || SKIP_NAMES.include?(name)
  end

  def folder_fingerprint(dir)
    max_mtime = 0
    total = 0
    dir.find do |path|
      next unless path.file?

      stat = path.stat
      max_mtime = [max_mtime, stat.mtime.to_i].max
      total += stat.size
    end
    { mtime: max_mtime, byte_size: total }
  end

  def index_folder(dir, folder_name, fingerprint)
    model = @library.vibe_models.find_or_initialize_by(folder_name: folder_name)
    model.title = humanize(folder_name)
    model.synopsis ||= read_synopsis(dir)
    model.folder_mtime = Time.at(fingerprint[:mtime])
    model.byte_size = fingerprint[:byte_size]
    model.uploaded_by ||= @uploaded_by
    model.save!

    seen_paths = []
    dir.find do |path|
      next unless path.file?
      next if SKIP_NAMES.include?(path.basename.to_s)

      rel = path.relative_path_from(dir).to_s
      seen_paths << rel
      upsert_asset(model, path, rel)
    end

    model.assets.where.not(relative_path: seen_paths).find_each(&:destroy)
    model.update!(asset_count: model.assets.count)
    assign_default_tags(model)
    SearchIndex.enqueue(model)
  end

  def upsert_asset(model, path, relative_path)
    stat = path.stat
    asset = model.assets.find_or_initialize_by(relative_path: relative_path)
    changed = asset.new_record? || asset.byte_size != stat.size || asset.mtime.to_i != stat.mtime.to_i

    asset.filename = path.basename.to_s
    asset.kind = detect_kind(path)
    asset.byte_size = stat.size
    asset.mtime = stat.mtime
    asset.uploaded_by ||= @uploaded_by if asset.new_record?
    asset.content_digest = digest_if_small(path, stat.size) if changed
    asset.save!

    if asset.archive? && (changed || asset.archive_members.none?)
      begin
        ArchiveIndexer.new(asset).index!
        DerivePreviewJob.perform_later(asset.id)
      rescue StandardError => e
        Rails.logger.warn("[LibraryScanner] archive index failed asset=#{asset.id}: #{e.class}: #{e.message}")
      end
    elsif (asset.mesh? || asset.image?) && changed
      DerivePreviewJob.perform_later(asset.id)
    end
    asset
  end

  def detect_kind(path)
    ext = path.extname.delete(".").downcase
    return ext if ext.present?

    "file"
  end

  def digest_if_small(path, size)
    return if size > 8.megabytes

    Digest::SHA256.file(path).hexdigest
  end

  def read_synopsis(dir)
    %w[readme.txt README.txt notes.txt synopsis.txt].each do |name|
      file = dir.join(name)
      return file.read.truncate(2_000) if file.file?
    end
    nil
  end

  def assign_default_tags(model)
    kinds = model.assets.pluck(:kind).uniq
    kinds.each do |kind|
      tag = Tag.find_or_create_by!(name: kind)
      model.tag_assignments.find_or_create_by!(tag: tag)
    end
  end

  def humanize(folder_name)
    folder_name.tr("_-", " ").squeeze(" ").strip.split.map(&:capitalize).join(" ")
  end
end
