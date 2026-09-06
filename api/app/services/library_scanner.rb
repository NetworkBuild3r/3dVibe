class LibraryScanner
  SKIP_NAMES = %w[. .. .DS_Store Thumbs.db].freeze
  NFS_STAT_ERRORS = [Errno::ENOENT, Errno::EACCES, Errno::ESTALE].freeze

  def initialize(library, uploaded_by: nil, budget: nil, trigger: nil)
    @library = library
    @uploaded_by = uploaded_by
    @budget = budget || ScanBudget.from_env
    @trigger = trigger
  end

  def scan!(path_prefix: nil, run: nil)
    @path_prefix = path_prefix.to_s.presence
    @run = run || start_run!
    @run.update!(status: ScanRun::RUNNING, started_at: @run.started_at || Time.current, finished_at: nil)

    root = Pathname.new(@library.root_path)
    raise ArgumentError, "Library root is not a directory: #{root}" unless root.directory?

    @disk_folders = list_model_folders(root)

    if @path_prefix.blank? && @run.phase == ScanRun::PHASE_PRUNE
      finish_or_continue_prune!
      return @run
    end

    last_completed = @run.resume_after
    @disk_folders.each do |folder_name|
      if @budget.time_exceeded?
        budget_stop!(last_completed)
        return @run
      end

      cursor = @library.scan_cursors.find_or_initialize_by(path_prefix: folder_name)
      if skip_already_walked?(folder_name, cursor)
        next
      end

      if @budget.folder_exceeded? && cursor.resume_relative_path.blank?
        budget_stop!(last_completed)
        return @run
      end

      outcome = process_folder(root.join(folder_name), folder_name, cursor)
      @run.folders_seen += 1

      case outcome
      when :budgeted
        persist_run!(status: ScanRun::BUDGETED, budget_exhausted: true, finished_at: Time.current)
        return @run
      when :skipped
        @run.folders_skipped += 1
        last_completed = folder_name
        @run.resume_after = folder_name
      when :fresh
        @run.folders_skipped += 1
        @budget.see_folder!
        last_completed = folder_name
        @run.resume_after = folder_name
      when :indexed
        @run.folders_indexed += 1
        @budget.see_folder!
        last_completed = folder_name
        @run.resume_after = folder_name
      when :error
        last_completed = folder_name
        @run.resume_after = folder_name
      end

      persist_run!
    end

    if @path_prefix.blank?
      @run.phase = ScanRun::PHASE_PRUNE
      @run.resume_after = nil
      persist_run!
      finish_or_continue_prune!
    else
      prune_missing_target!
      @run.mark_completed!
    end

    @run
  rescue StandardError => e
    @run&.fail!(e)
    raise
  end

  private

  def start_run!
    @library.scan_runs.create!(
      status: ScanRun::RUNNING,
      trigger: @trigger.presence || (@path_prefix ? ScanRun::TRIGGER_TARGETED : ScanRun::TRIGGER_INLINE),
      path_prefix: @path_prefix,
      triggered_by: @uploaded_by,
      phase: ScanRun::PHASE_WALK,
      started_at: Time.current
    )
  end

  def skip_already_walked?(folder_name, cursor)
    return false if @path_prefix.present?
    return false if @run.resume_after.blank?
    return false if cursor.resume_relative_path.present?

    folder_name <= @run.resume_after
  end

  def process_folder(dir, folder_name, cursor)
    unless dir.directory?
      @run.record_error(folder_name, ArgumentError.new("not a directory"))
      return :error
    end

    dir_stat = dir.lstat
    if cursor.skip_deep_walk?(dir_stat)
      return :skipped
    end

    @run.deep_walks += 1
    index_folder(dir, folder_name, cursor, dir_stat)
  rescue *NFS_STAT_ERRORS => e
    @run.record_error(folder_name, e)
    :error
  rescue StandardError => e
    @run.record_error(folder_name, e)
    :error
  end

  def index_folder(dir, folder_name, cursor, dir_stat)
    model = @library.vibe_models.find_or_initialize_by(folder_name: folder_name)
    model.title = humanize(folder_name)
    model.synopsis ||= read_synopsis(dir)
    model.uploaded_by ||= @uploaded_by
    model.save!

    seen_paths = []
    max_mtime = 0
    total = 0
    file_count = 0
    changed_count = 0
    start_after = cursor.resume_relative_path
    last_rel = nil
    completed = true

    each_regular_file(dir) do |path, rel, stat|
      file_count += 1
      max_mtime = [max_mtime, stat.mtime.to_i].max
      total += stat.size

      if start_after.present? && rel <= start_after
        seen_paths << rel
        last_rel = rel
        next
      end

      if @budget.file_or_time_exceeded?
        completed = false
        break
      end

      changed = upsert_asset(model, path, rel, stat)
      changed_count += 1 if changed
      @budget.see_file!
      @run.files_seen += 1
      @run.files_changed += 1 if changed
      seen_paths << rel
      last_rel = rel
    end

    if completed
      model.assets.where.not(relative_path: seen_paths).find_each(&:destroy)
      model.update!(
        asset_count: model.assets.count,
        folder_mtime: Time.at(max_mtime),
        byte_size: total
      )
      assign_default_tags(model)
      SearchIndex.enqueue(model)
      cursor.remember!(mtime: max_mtime, byte_size: total, file_count: file_count, dir_stat: dir_stat)
      return :fresh if changed_count.zero? && start_after.blank?

      return :indexed
    end

    model.update!(folder_mtime: Time.at(max_mtime), byte_size: total)
    cursor.update!(resume_relative_path: last_rel)
    :budgeted
  end

  def each_regular_file(dir)
    entries = []
    dir.find do |path|
      next if path == dir

      begin
        stat = path.lstat
      rescue *NFS_STAT_ERRORS
        next
      end
      next unless stat.file?
      next if SKIP_NAMES.include?(path.basename.to_s)

      entries << [path, path.relative_path_from(dir).to_s, stat]
    end
    entries.sort_by! { |_, rel, _| rel }
    entries.each { |path, rel, stat| yield path, rel, stat }
  end

  def upsert_asset(model, path, relative_path, stat)
    asset = model.assets.find_or_initialize_by(relative_path: relative_path)
    changed = asset.new_record? ||
      asset.byte_size != stat.size ||
      asset.mtime.to_i != stat.mtime.to_i ||
      asset.inode.to_i != stat.ino.to_i

    asset.filename = path.basename.to_s
    asset.kind = detect_kind(path)
    asset.byte_size = stat.size
    asset.mtime = stat.mtime
    asset.inode = stat.ino
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

    changed
  end

  def finish_or_continue_prune!
    if dangerous_empty_prune?
      @run.record_error("prune", ArgumentError.new(
        "refusing to prune: library root listed zero model folders (empty mount or NFS outage). " \
        "Set VIBE_SCAN_ALLOW_EMPTY_PRUNE=1 to override."
      ))
      @run.mark_completed!
      return
    end

    stale_names = disappeared_names.first(ScanSettings.prune_batch)
    if stale_names.empty?
      @run.mark_completed!
      return
    end

    pruned = 0
    @library.vibe_models.where(folder_name: stale_names).find_each do |model|
      break if @budget.time_exceeded?

      model.destroy
      pruned += 1
    end
    @library.scan_cursors.where(path_prefix: stale_names).delete_all
    @run.pruned_count += pruned
    persist_run!

    if disappeared_names.any?
      persist_run!(status: ScanRun::BUDGETED, budget_exhausted: true, finished_at: Time.current, phase: ScanRun::PHASE_PRUNE)
      return
    end

    ReindexSearchJob.perform_later(@library.id)
    @run.mark_completed!
  end

  def prune_missing_target!
    return if @disk_folders.include?(@path_prefix)

    model = @library.vibe_models.find_by(folder_name: @path_prefix)
    return unless model

    model.destroy
    @library.scan_cursors.where(path_prefix: @path_prefix).delete_all
    @run.pruned_count += 1
    ReindexSearchJob.perform_later(@library.id)
  end

  def disappeared_names
    folder_names = @disk_folders
    model_names = @library.vibe_models.where.not(folder_name: folder_names).pluck(:folder_name)
    cursor_names = @library.scan_cursors.where.not(path_prefix: folder_names).pluck(:path_prefix)
    (model_names + cursor_names).uniq.sort
  end

  def dangerous_empty_prune?
    @disk_folders.empty? && @library.vibe_models.exists? && !ScanSettings.allow_empty_prune?
  end

  def budget_stop!(last_completed)
    @run.resume_after = last_completed
    persist_run!(
      status: ScanRun::BUDGETED,
      budget_exhausted: true,
      finished_at: Time.current,
      last_error: @run.last_error.presence || "budget exhausted: #{@budget.reason}"
    )
  end

  def persist_run!(attrs = {})
    @run.assign_attributes(attrs)
    @run.save!
  end

  def list_model_folders(root)
    if @path_prefix
      folder = LibraryPathJail.new(root).normalize_folder(@path_prefix)
      target = root.join(folder)
      return target.directory? ? [folder] : []
    end

    names = []
    Dir.each_child(root.to_s) do |name|
      next if hidden_name?(name)

      names << name if File.directory?(File.join(root.to_s, name))
    end
    names.sort
  rescue *NFS_STAT_ERRORS => e
    raise ArgumentError, "Cannot list library root: #{e.message}"
  end

  def hidden_name?(name)
    name.start_with?(".") || SKIP_NAMES.include?(name)
  end

  def detect_kind(path)
    ext = path.extname.delete(".").downcase
    return ext if ext.present?

    "file"
  end

  def digest_if_small(path, size)
    return if size > 32.megabytes

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
