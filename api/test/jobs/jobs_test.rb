require "test_helper"
require "fileutils"

class JobsTest < ActiveJob::TestCase
  test "incremental scan job runs the scanner" do
    root = Rails.root.join("tmp/job-lib-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(root.join("only"))
    File.write(root.join("only/a.txt"), "x")
    require "zip"
    Zip::File.open(root.join("only/minis.zip"), Zip::File::CREATE) do |zip|
      zip.get_output_stream("hero.stl") { |io| io.write("solid x\nendsolid x\n") }
    end
    library = Library.create!(name: "Jobs", root_path: root.to_s)

    IncrementalScanJob.perform_now(library.id)
    assert_equal 1, library.vibe_models.count
    archive = library.vibe_models.first.assets.find_by!(filename: "minis.zip")
    assert_includes archive.archive_members.pluck(:internal_path), "hero.stl"
  ensure
    FileUtils.rm_rf(root)
  end

  test "preview and apply jobs enqueue without error" do
    user = create_owner!
    library = Library.create!(name: "Jobs", root_path: "/tmp/unused")
    model = library.vibe_models.create!(folder_name: "x", title: "X")
    asset = model.assets.create!(relative_path: "a.stl", filename: "a.stl", kind: "stl")
    pending = library.curation_proposals.create!(kind: "tag", summary: "t", payload: {})
    approved = library.curation_proposals.create!(
      kind: "tag",
      summary: "ready",
      payload: { "model_id" => model.id, "tag" => "job" },
      status: CurationProposal::APPROVED
    )

    assert_nothing_raised do
      DerivePreviewJob.perform_now(asset.id)
      GenerateCoverJob.perform_now(
        "library_id" => library.id,
        "model_id" => model.id,
        "asset_id" => asset.id,
        "jailed_path" => "x/a.stl",
        "mtime" => 0,
        "content_hash" => nil,
        "budget" => { "max_px" => 512, "max_bytes" => 250_000 }
      )
      ApplyCurationProposalJob.perform_now(pending.id)
      ApplyCurationProposalJob.perform_now(approved.id)
    end
    assert_equal VibeModel::COVER_FAILED, model.reload.cover_status
    refute pending.reload.applied?
    assert approved.reload.applied?
    assert_includes model.tags.reload.map(&:name), "job"
    assert user.present?
  end

  test "dispatch print job completes the mock adapter" do
    root = Rails.root.join("tmp/print-job-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(root.join("only"))
    File.write(root.join("only/a.stl"), "solid a\nendsolid a\n")
    user = create_owner!
    library = Library.create!(name: "Print jobs", root_path: root.to_s)
    Membership.create!(user: user, library: library, role: Membership::OWNER)
    LibraryScanner.new(library).scan!
    model = library.vibe_models.find_by!(folder_name: "only")
    asset = model.assets.find_by!(filename: "a.stl")
    printer = library.printers.create!(name: "Mock", host: "127.0.0.1", protocol_type: Printer::MOCK)
    job = PrintDispatch.create!(
      library: library,
      printer: printer,
      vibe_model: model,
      asset: asset,
      requested_by: user,
      status: PrintDispatch::QUEUED,
      filename: asset.filename
    )

    DispatchPrintJob.perform_now(job.id)
    assert_equal PrintDispatch::SUCCEEDED, job.reload.status
  ensure
    FileUtils.rm_rf(root)
  end

  test "scheduled scan job enqueues an incremental scan per library" do
    library = Library.create!(name: "Sched", root_path: "/tmp/unused-scan")
    assert_enqueued_with(job: IncrementalScanJob, args: [library.id, nil, nil, ScanRun::TRIGGER_SCHEDULED], queue: "scan") do
      ScheduledScanJob.perform_now
    end
  end

  test "scan jobs enqueue on the isolated scan queue" do
    library = Library.create!(name: "Queued", root_path: "/tmp/unused-scan-q")
    assert_enqueued_with(job: IncrementalScanJob, queue: ScanSettings.queue) do
      IncrementalScanJob.perform_later(library.id)
    end
    assert_enqueued_with(job: ScheduledScanJob, queue: ScanSettings.queue) do
      ScheduledScanJob.perform_later
    end
    assert_enqueued_with(job: DispatchPrintJob, queue: "print") do
      DispatchPrintJob.perform_later(1)
    end
  end

  test "VIBE_SCAN_QUEUE retargets IncrementalScanJob without touching print" do
    previous = ENV["VIBE_SCAN_QUEUE"]
    ENV["VIBE_SCAN_QUEUE"] = "nfs-walk"
    library = Library.create!(name: "Retarget", root_path: "/tmp/unused-scan-r")
    assert_enqueued_with(job: IncrementalScanJob, queue: "nfs-walk") do
      IncrementalScanJob.perform_later(library.id)
    end
    assert_enqueued_with(job: DispatchPrintJob, queue: "print") do
      DispatchPrintJob.perform_later(1)
    end
  ensure
    if previous.nil?
      ENV.delete("VIBE_SCAN_QUEUE")
    else
      ENV["VIBE_SCAN_QUEUE"] = previous
    end
  end

  test "search index jobs no-op without Meili" do
    user = create_owner!
    library = Library.create!(name: "Search jobs", root_path: "/tmp/unused")
    model = library.vibe_models.create!(folder_name: "x", title: "X")

    assert_nothing_raised do
      IndexVibeModelJob.perform_now(model.id)
      BulkIndexVibeModelsJob.perform_now([model.id])
      RemoveVibeModelIndexJob.perform_now(model.id)
      ReindexSearchJob.perform_now(library.id)
    end
    assert user.present?
  end

  test "analyze duplicates job persists groups and geometry job writes a digest" do
    root = Rails.root.join("tmp/dup-job-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(root.join("a"))
    FileUtils.mkdir_p(root.join("b"))
    File.write(root.join("a/horn.stl"), "solid horn\nendsolid horn\n")
    File.write(root.join("b/horn.stl"), "solid horn\nendsolid horn\n")
    write_ascii_stl(root.join("a/cube.stl"))
    library = Library.create!(name: "Dup jobs", root_path: root.to_s)
    LibraryScanner.new(library, budget: ScanBudget.unlimited).scan!
    empty = library.vibe_models.find_by!(folder_name: "a").assets.find_by!(filename: "horn.stl")
    cube = library.vibe_models.find_by!(folder_name: "a").assets.find_by!(filename: "cube.stl")

    AnalyzeDuplicatesJob.perform_now(library.id)
    assert library.duplicate_groups.open.exists?(reason: DuplicateGroup::REASON_CONTENT_HASH)
    assert_match(/\Amesh:v1:[0-9a-f]{64}\z/, cube.reload.geometry_digest)

    assert_nothing_raised { ComputeGeometryDigestJob.perform_now(empty.id) }
    assert_nil empty.reload.geometry_digest
    ComputeGeometryDigestJob.perform_now(cube.id)
    assert_match(/\Amesh:v1:[0-9a-f]{64}\z/, cube.reload.geometry_digest)
  ensure
    FileUtils.rm_rf(root)
  end

  test "fetch job upserts stub proposals" do
    root = Rails.root.join("tmp/fetch-lib-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(root.join("only"))
    File.write(root.join("only/a.txt"), "x")
    library = Library.create!(name: "Fetch", root_path: root.to_s, last_error: "stale")
    LibraryScanner.new(library).scan!

    FetchCurationProposalsJob.perform_now(library.id)
    assert library.curation_proposals.pending.exists?
    library.reload
    assert_nil library.last_error
    assert library.last_polled_at.present?
    assert_equal "stub", library.last_provider
  ensure
    FileUtils.rm_rf(root)
  end

  test "fetch job records last_error when the sidecar fails" do
    root = Rails.root.join("tmp/fetch-fail-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(root.join("only"))
    File.write(root.join("only/a.txt"), "x")
    library = Library.create!(name: "Fetch fail", root_path: root.to_s)
    LibraryScanner.new(library).scan!

    previous = ENV["VIBE_CURATOR_URL"]
    ENV["VIBE_CURATOR_URL"] = "http://127.0.0.1:1"
    assert_raises(CurationHttpClient::Error) { FetchCurationProposalsJob.perform_now(library.id) }
    library.reload
    assert library.last_error.present?
    assert_match(/unreachable|HTTP|curator/i, library.last_error)
    assert library.last_polled_at.present?
  ensure
    ENV["VIBE_CURATOR_URL"] = previous
    FileUtils.rm_rf(root)
  end
end
