namespace :vibe do
  desc "Incrementally scan a library (id= or all). Honors VIBE_SCAN_* budgets; re-run to resume."
  task scan: :environment do
    scope = ENV["LIBRARY_ID"].present? ? Library.where(id: ENV["LIBRARY_ID"]) : Library.all
    scope.find_each do |library|
      puts "Scanning #{library.name} at #{library.root_path}"
      run = LibraryScanner.new(library, trigger: ScanRun::TRIGGER_RAKE).scan!(path_prefix: ENV["PATH_PREFIX"])
      puts "  -> #{library.vibe_models.count} models  status=#{run.status} " \
           "files=#{run.files_seen} indexed=#{run.folders_indexed} skipped=#{run.folders_skipped} " \
           "pruned=#{run.pruned_count} errors=#{run.error_count}"
      puts "  -> budgeted at #{run.resume_after.inspect}; re-run vibe:scan to continue" if run.budgeted?
      puts "  -> #{run.last_error}" if run.last_error.present?
    end
    if MeilisearchClient.configured?
      result = SearchIndex.new.reindex_all!(
        ENV["LIBRARY_ID"].present? ? VibeModel.where(library_id: ENV["LIBRARY_ID"]) : VibeModel.all
      )
      puts "Search reindex: #{result.inspect}"
    end
  end

  desc "Queue IncrementalScanJob for every library (or LIBRARY_ID=)"
  task enqueue_scan: :environment do
    scope = ENV["LIBRARY_ID"].present? ? Library.where(id: ENV["LIBRARY_ID"]) : Library.all
    scope.find_each { |library| IncrementalScanJob.perform_later(library.id, nil, nil, ScanRun::TRIGGER_RAKE) }
    puts "Queued scan jobs"
  end

  # INIT-020/SPEC-009 — explicit owner action (D-5). Not a civil-hour cron.
  # Dry-run by default. APPLY=1 wipes catalog rows only (NFS files stay).
  desc "Report or wipe first-level mega-models (WIPE=mega|all) then enqueue category_model scan. APPLY=1 LIBRARY_ID= USER_ID= required to apply."
  task rebuild_catalog: :environment do
    apply = ActiveModel::Type::Boolean.new.cast(ENV["APPLY"]) == true
    wipe = ENV["WIPE"].presence || CatalogRebuild::WIPE_MEGA
    if apply
      abort "APPLY=1 requires LIBRARY_ID=" if ENV["LIBRARY_ID"].blank?
      abort "APPLY=1 requires USER_ID= of a library owner" if ENV["USER_ID"].blank?
    end

    actor = ENV["USER_ID"].present? ? User.find(ENV["USER_ID"]) : nil
    scope = ENV["LIBRARY_ID"].present? ? Library.where(id: ENV["LIBRARY_ID"]) : Library.all
    scope.find_each do |library|
      result = CatalogRebuild.new(library, apply: apply, wipe: wipe, actor: actor).call
      puts "library=#{result[:library_id]} name=#{result[:library_name]} wipe=#{result[:wipe]} apply=#{result[:apply]} " \
           "targets=#{result[:models].size} deleted=#{result[:deleted]} scan_enqueued=#{result[:scan_enqueued]} " \
           "files_unlinked=#{result[:files_unlinked]}"
      result[:models].each do |model|
        puts "  model id=#{model[:id]} folder=#{model[:folder_name]} title=#{model[:title]}"
      end
    end
  rescue CatalogRebuild::Forbidden => e
    abort e.message
  end

  desc "Queue a print against the mock (or named) printer. ASSET_ID= or MODEL_FOLDER= PRINTER_ID="
  task print: :environment do
    library = ENV["LIBRARY_ID"].present? ? Library.find(ENV["LIBRARY_ID"]) : Library.first!
    printer = if ENV["PRINTER_ID"].present?
      library.printers.find(ENV["PRINTER_ID"])
    else
      library.printers.enabled.find_by!(protocol_type: Printer::MOCK)
    end
    model = if ENV["MODEL_ID"].present?
      library.vibe_models.find(ENV["MODEL_ID"])
    elsif ENV["MODEL_FOLDER"].present?
      library.vibe_models.find_by!(folder_name: ENV["MODEL_FOLDER"])
    else
      library.vibe_models.joins(:assets).find_by(assets: { filename: "horn.stl" }) ||
        library.vibe_models.joins(:assets).where(assets: { kind: Asset::MESH_KINDS }).first!
    end
    asset = if ENV["ASSET_ID"].present?
      model.assets.find(ENV["ASSET_ID"])
    else
      model.assets.find_by(kind: Asset::MESH_KINDS) || model.assets.first!
    end
    owner = library.owner || User.first!
    job = PrintDispatch.create!(
      library: library,
      printer: printer,
      vibe_model: model,
      asset: asset,
      requested_by: owner,
      status: PrintDispatch::QUEUED,
      protocol_type: printer.protocol_type,
      filename: asset.filename,
      printer_hint: printer.name,
      note: "Queued via rake vibe:print"
    )
    DispatchPrintJob.perform_now(job.id)
    job.reload
    puts "Print job #{job.id} #{job.status} progress=#{job.progress} file=#{job.filename} printer=#{printer.name}"
    puts "  #{job.note}" if job.note.present?
    abort "print failed" if job.status == PrintDispatch::FAILED
  end

  desc "Rebuild the Meilisearch vibe_models index (no-op if MEILI_URL is blank or Meili is down)"
  task reindex: :environment do
    scope = ENV["LIBRARY_ID"].present? ? VibeModel.where(library_id: ENV["LIBRARY_ID"]) : VibeModel.all
    result = SearchIndex.new.reindex_all!(scope)
    puts "Reindex: #{result.inspect} (#{scope.count} catalog models, url=#{MeilisearchClient.url || 'unset'})"
  end

  desc "Poll the curation sidecar (or in-process stub) and upsert pending proposals"
  task curate: :environment do
    scope = ENV["LIBRARY_ID"].present? ? Library.where(id: ENV["LIBRARY_ID"]) : Library.all
    scope.find_each do |library|
      records = CurationSidecar.new(library).ingest_remote!
      library.reload
      puts "Library #{library.name}: upserted #{records.size} proposal(s) " \
           "provider=#{library.last_provider || '—'} polled=#{library.last_polled_at || '—'}"
      puts "  last_error=#{library.last_error}" if library.last_error.present?
    end
  end
end
