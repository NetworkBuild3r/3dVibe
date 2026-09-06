namespace :vibe do
  desc "Incrementally scan a library (id= or all)"
  task scan: :environment do
    scope = ENV["LIBRARY_ID"].present? ? Library.where(id: ENV["LIBRARY_ID"]) : Library.all
    scope.find_each do |library|
      puts "Scanning #{library.name} at #{library.root_path}"
      LibraryScanner.new(library).scan!
      puts "  -> #{library.vibe_models.count} models"
    end
  end

  desc "Queue IncrementalScanJob for every library"
  task enqueue_scan: :environment do
    Library.find_each { |library| IncrementalScanJob.perform_later(library.id) }
    puts "Queued scan jobs"
  end

  desc "Poll the curation sidecar (or in-process stub) and upsert pending proposals"
  task curate: :environment do
    scope = ENV["LIBRARY_ID"].present? ? Library.where(id: ENV["LIBRARY_ID"]) : Library.all
    scope.find_each do |library|
      records = CurationSidecar.new(library).ingest_remote!
      puts "Library #{library.name}: upserted #{records.size} proposal(s)"
    end
  end
end
