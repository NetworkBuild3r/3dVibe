# INIT-020/SPEC-009 — owner-gated catalog wipe + rescan. Drops invalid first-level
# mega-models (or a documented full wipe). Never unlinks NFS / library files.
class CatalogRebuild
  class Forbidden < StandardError; end

  WIPE_MEGA = "mega"
  WIPE_ALL = "all"
  WIPES = [WIPE_MEGA, WIPE_ALL].freeze
  FIRST_LEVEL_SQL = "folder_name NOT LIKE '%/%'".freeze
  DESTROY_BATCH = 200

  def initialize(library, apply: false, wipe: WIPE_MEGA, actor: nil)
    @library = library
    @apply = ActiveModel::Type::Boolean.new.cast(apply) == true
    @wipe = wipe.to_s.strip.downcase.presence || WIPE_MEGA
    @actor = actor
  end

  def call
    validate_wipe!
    authorize_apply! if @apply

    models = target_scope.to_a
    report = base_report(models)
    return log_and_return(report) unless @apply

    deleted = destroy_catalog_rows!(models)
    clear_stale_cursors!
    IncrementalScanJob.perform_later(@library.id, nil, @actor&.id, ScanRun::TRIGGER_REBUILD)

    report[:deleted] = deleted
    report[:scan_enqueued] = true
    log_and_return(report)
  end

  private

  def validate_wipe!
    raise ArgumentError, "unknown wipe #{@wipe.inspect} (mega or all)" unless WIPES.include?(@wipe)

    return unless @wipe == WIPE_MEGA && @library.layout_mode != Library::LAYOUT_CATEGORY_MODEL

    raise ArgumentError,
          "mega wipe requires category_model layout (use wipe=all for a documented full catalog wipe)"
  end

  def authorize_apply!
    raise Forbidden, "apply requires a library owner (USER_ID= of an owner)" if @actor.blank?
    return if @actor.owner_of?(@library)

    raise Forbidden, "apply requires a library owner"
  end

  def target_scope
    scope = @library.vibe_models.order(:id)
    return scope if @wipe == WIPE_ALL

    scope.where(FIRST_LEVEL_SQL)
  end

  def base_report(models)
    {
      library_id: @library.id,
      library_name: @library.name,
      wipe: @wipe,
      apply: @apply,
      models: models.map { |model| { id: model.id, folder_name: model.folder_name, title: model.title } },
      deleted: 0,
      scan_enqueued: false,
      files_unlinked: 0
    }
  end

  # Catalog rows + Meili removal callbacks only. Asset#destroy does not touch disk.
  def destroy_catalog_rows!(models)
    models.each do |model|
      model.assets.find_each(batch_size: DESTROY_BATCH, &:destroy)
      model.destroy!
    end
    models.size
  end

  def clear_stale_cursors!
    cursors = @library.scan_cursors
    cursors = cursors.where("path_prefix NOT LIKE '%/%'") if @wipe == WIPE_MEGA
    cursors.delete_all
  end

  def log_and_return(report)
    Rails.logger.info(
      "[CatalogRebuild] library=#{report[:library_id]} apply=#{report[:apply]} wipe=#{report[:wipe]} " \
      "targets=#{report[:models].size} deleted=#{report[:deleted]} scan_enqueued=#{report[:scan_enqueued]} " \
      "actor=#{@actor&.id} files_unlinked=#{report[:files_unlinked]}"
    )
    report
  end
end
