# Applies an approved CurationProposal.
# Tags write only to the catalog. Rename/move/merge stay inside LibraryPathJail.
# Never deletes user files. Merge may remove empty directories after a move.
class CurationApplier
  JUNK_NAMES = %w[.DS_Store Thumbs.db].freeze

  def self.humanize(folder_name)
    folder_name.to_s.tr("_-", " ").squeeze(" ").strip.split.map(&:capitalize).join(" ")
  end

  def initialize(proposal)
    @proposal = proposal
    @library = proposal.library
    @jail = LibraryPathJail.new(@library.root_path)
    @touched = []
  end

  def apply!
    return @proposal if @proposal.applied?
    return record_error("not_approved") unless @proposal.approved?

    result =
      case @proposal.kind
      when "tag" then apply_tag
      when "rename" then apply_rename
      when "move" then apply_move
      when "merge" then apply_merge
      when "organize" then apply_organize
      else
        { ok: false, error: "unsupported_kind" }
      end

    if result[:ok]
      record_success(result)
      enqueue_scans!
      enqueue_search!(result)
    else
      record_error(result[:error].presence || "apply_failed", result)
    end
    @proposal
  rescue ArgumentError, ActiveRecord::RecordInvalid, Errno::ENOENT, Errno::EACCES => e
    record_error(e.message)
    @proposal
  end

  private

  def payload
    @proposal.payload_hash
  end

  def apply_tag
    models = resolve_models
    tags = tag_names
    return { ok: true, noop: true, reason: "no_targets" } if models.empty? || tags.empty?

    assigned = 0
    models.each do |model|
      tags.each do |name|
        tag = Tag.find_or_create_by!(name: name)
        assignment = model.tag_assignments.find_or_create_by!(tag: tag)
        assigned += 1 if assignment.previously_new_record? || assignment.saved_change_to_id?
      end
    end
    { ok: true, action: "tag", model_ids: models.map(&:id), tags: tags, assigned: assigned }
  end

  def apply_rename
    model = resolve_primary_model
    return { ok: false, error: "model_not_found" } unless model

    destination = @jail.normalize_model_folder(payload["to"].presence || payload["folder_name"].presence || "")
    rename_model_folder!(model, destination, title: payload["title"])
  end

  def apply_move
    if payload["relative_path"].present? || payload["asset_id"].present?
      return move_asset!
    end

    model = resolve_primary_model
    return { ok: false, error: "model_not_found" } unless model

    destination = @jail.normalize_model_folder(@proposal.destination_folder.to_s)
    rename_model_folder!(model, destination, title: payload["title"])
  end

  def apply_merge
    source, target = resolve_merge_pair
    return { ok: false, error: "merge_pair_not_found" } unless source && target
    return { ok: false, error: "merge_same_model" } if source.id == target.id

    source_dir = @jail.folder_path(source.folder_name)
    target_dir = @jail.folder_path(target.folder_name)
    return { ok: false, error: "source_missing" } unless source_dir.directory?
    return { ok: false, error: "target_missing" } unless target_dir.directory?

    moved = []
    source_dir.find do |path|
      next unless path.file?
      next if JUNK_NAMES.include?(path.basename.to_s)

      rel = path.relative_path_from(source_dir).to_s
      dest = @jail.join(target.folder_name, "#{source.folder_name}/#{rel}")
      FileUtils.mkdir_p(dest.dirname)
      FileUtils.mv(path.to_s, dest.to_s)
      moved << dest.relative_path_from(target_dir).to_s
    end

    emptied = remove_empty_tree!(source_dir)
    @touched << target.folder_name
    @touched << source.folder_name

    if emptied
      source.destroy!
      @library.scan_cursors.where(path_prefix: source.folder_name).delete_all
    end

    {
      ok: true,
      action: "merge",
      source_id: source.id,
      target_id: target.id,
      moved: moved,
      source_removed: emptied
    }
  end

  def apply_organize
    if @proposal.destination_folder.present? && resolve_primary_model
      return apply_move
    end

    apply_tag
  end

  def move_asset!
    model = resolve_primary_model
    return { ok: false, error: "model_not_found" } unless model

    dest_folder = @jail.normalize_model_folder(@proposal.destination_folder.to_s)
    dest_model = @library.vibe_models.find_by(folder_name: dest_folder)
    return { ok: false, error: "destination_model_not_found" } unless dest_model

    relative = if payload["asset_id"].present?
      model.assets.find_by(id: payload["asset_id"])&.relative_path
    else
      payload["relative_path"]
    end
    return { ok: false, error: "asset_not_found" } if relative.blank?

    source = @jail.join(model.folder_name, relative)
    dest_relative = payload["destination_relative_path"].presence || "#{model.folder_name}/#{relative}"
    dest = @jail.join(dest_folder, dest_relative)
    return { ok: false, error: "source_file_missing" } unless source.file?

    FileUtils.mkdir_p(dest.dirname)
    FileUtils.mv(source.to_s, dest.to_s)
    @touched << model.folder_name
    @touched << dest_folder
    { ok: true, action: "move_asset", from: source.to_s, to: dest.to_s }
  end

  def rename_model_folder!(model, destination, title: nil)
    raise ArgumentError, "destination exists" if destination != model.folder_name && (
      @library.vibe_models.exists?(folder_name: destination) || @jail.folder_path(destination).exist?
    )

    source_dir = @jail.folder_path(model.folder_name)
    dest_dir = @jail.folder_path(destination)
    FileUtils.mv(source_dir.to_s, dest_dir.to_s) if source_dir.exist? && source_dir != dest_dir

    old_name = model.folder_name
    model.update!(folder_name: destination, title: title.presence || self.class.humanize(destination))
    retarget_cursor!(old_name, destination)
    @touched << destination
    @touched << old_name
    { ok: true, action: "rename", from: old_name, to: destination, model_id: model.id }
  end

  def retarget_cursor!(old_name, new_name)
    return if old_name == new_name

    @library.scan_cursors.where(path_prefix: new_name).delete_all
    cursor = @library.scan_cursors.find_by(path_prefix: old_name)
    cursor&.update!(path_prefix: new_name)
  end

  def resolve_models
    ids = [payload["model_id"], *Array(payload["model_ids"])].compact
    folders = [payload["folder_name"], payload["from"], *Array(payload["folder_names"])].compact
    scope = @library.vibe_models
    found = []
    found.concat(scope.where(id: ids).to_a) if ids.any?
    found.concat(scope.where(folder_name: folders).to_a) if folders.any?
    found.uniq
  end

  def resolve_primary_model
    id = payload["model_id"].presence || Array(payload["model_ids"]).first
    folder = payload["folder_name"].presence || payload["from"].presence
    @library.vibe_models.find_by(id: id) || @library.vibe_models.find_by(folder_name: folder)
  end

  def resolve_merge_pair
    source = @library.vibe_models.find_by(id: payload["source_id"].presence || payload["left_id"]) ||
             @library.vibe_models.find_by(folder_name: payload["from"])
    target = @library.vibe_models.find_by(id: payload["target_id"].presence || payload["right_id"]) ||
             @library.vibe_models.find_by(folder_name: payload["to"].presence || payload["destination_folder"])
    [source, target]
  end

  def tag_names
    names = Array(payload["tags"])
    names << payload["tag"]
    names << payload["shelf"] if @proposal.organize?
    names.flatten.compact.map { |name| name.to_s.strip.downcase }.reject(&:blank?).uniq
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

  def record_success(result)
    @proposal.update!(applied_at: Time.current, apply_error: nil, result: result.merge(ok: true))
  end

  def record_error(message, result = {})
    @proposal.update!(apply_error: message, result: result.merge(ok: false, error: message))
    @proposal
  end

  def enqueue_scans!
    @touched.uniq.each do |prefix|
      next if prefix.blank?

      IncrementalScanJob.perform_later(@library.id, prefix)
    end
  end

  def enqueue_search!(result)
    ids = Array(result[:model_ids])
    ids << result[:source_id]
    ids << result[:target_id]
    ids.compact.uniq.each do |model_id|
      model = @library.vibe_models.find_by(id: model_id)
      SearchIndex.enqueue(model)
    end
  end
end
