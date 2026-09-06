require "test_helper"
require "fileutils"

class LibrariesScanTest < ActionDispatch::IntegrationTest
  def setup
    @root = Rails.root.join("tmp/api-scan-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(@root.join("horn"))
    File.write(@root.join("horn/notes.txt"), "signal")
    @password = "secret123"
    @owner = create_owner!(password: @password)
    @library = Library.create!(name: "Studio", root_path: @root.to_s)
    Membership.create!(user: @owner, library: @library, role: Membership::OWNER)
    LibraryScanner.new(@library, budget: ScanBudget.unlimited).scan!
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  test "owner sees scan status on index and show" do
    get "/api/v1/libraries", headers: auth_header(@owner)
    assert_response :success
    row = response.parsed_body.fetch("libraries").first
    assert_equal "completed", row.dig("scan", "status")
    assert row.dig("scan", "files_seen").to_i >= 1
    assert row.dig("scan", "budgets", "max_files").present?
    assert row["can_scan"]
    assert row.key?("curation")
    assert row["curation"].key?("last_polled_at")
    assert row["curation"].key?("last_provider")
    assert row["curation"].key?("last_error")

    get "/api/v1/libraries/#{@library.id}", headers: auth_header(@owner)
    assert_response :success
    body = response.parsed_body.fetch("library")
    assert_equal "completed", body.dig("scan", "status")
    assert_equal "done", body.dig("scan", "phase")
    assert body["scan"].key?("resume")
    assert body["scan_settings"]["max_files"].present?
    assert_equal "scan", body["scan_settings"]["queue"]
    assert_equal 1, body["scan_settings"]["concurrency"]
    assert_equal 5, body["scan_settings"]["worker_concurrency"]
    assert body["cursors"].any? { |cursor| cursor["path_prefix"] == "horn" }
  end

  test "owner can queue an on-demand scan" do
    post "/api/v1/libraries/#{@library.id}/scan", headers: auth_header(@owner), as: :json
    assert_response :accepted
    assert response.parsed_body["queued"]
    assert_equal ScanRun::QUEUED, response.parsed_body.dig("library", "scan", "status")
    assert_enqueued_with(job: IncrementalScanJob, args: [@library.id, nil, @owner.id, ScanRun::TRIGGER_API], queue: "scan")
  end

  test "GET scan exposes current and last runs with resume summary" do
    finished = @library.latest_scan_run
    finished.update!(status: ScanRun::COMPLETED, phase: ScanRun::PHASE_DONE, finished_at: 1.hour.ago, started_at: 2.hours.ago)
    current = @library.scan_runs.create!(
      status: ScanRun::BUDGETED,
      trigger: ScanRun::TRIGGER_API,
      phase: ScanRun::PHASE_WALK,
      path_prefix: nil,
      started_at: Time.current,
      budget_exhausted: true,
      resume_after: "horn",
      folders_seen: 1,
      files_seen: 4,
      last_error: "budget exhausted: files"
    )
    @library.scan_cursors.find_by!(path_prefix: "horn").update!(resume_relative_path: "notes.txt")

    get "/api/v1/libraries/#{@library.id}/scan", headers: auth_header(@owner)
    assert_response :success
    body = response.parsed_body
    assert_equal @library.id, body["library_id"]
    assert_equal current.id, body.dig("scan", "id")
    assert_equal ScanRun::BUDGETED, body.dig("scan", "status")
    assert_equal ScanRun::PHASE_WALK, body.dig("scan", "phase")
    assert_equal "horn", body.dig("scan", "resume", "resume_after")
    assert_equal "notes.txt", body.dig("scan", "resume", "resume_relative_path")
    assert_equal "horn", body.dig("scan", "resume", "path_prefix")
    assert_equal current.id, body.dig("current", "id")
    assert_equal finished.id, body.dig("last", "id")
    assert_equal ScanRun::COMPLETED, body.dig("last", "status")
    assert body.dig("scan", "budgets").key?("max_seconds")
  end

  test "library without a scan run reports idle plus budgets" do
    empty_root = Rails.root.join("tmp/api-scan-idle-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(empty_root)
    empty = Library.create!(name: "Empty", root_path: empty_root.to_s)
    Membership.create!(user: @owner, library: empty, role: Membership::OWNER)

    get "/api/v1/libraries/#{empty.id}/scan", headers: auth_header(@owner)
    assert_response :success
    body = response.parsed_body
    assert_equal "idle", body.dig("scan", "status")
    assert body.dig("scan", "budgets").key?("max_seconds")
    assert_nil body["current"]
    assert_nil body["last"]
    assert_nil body.dig("scan", "resume")
  ensure
    FileUtils.rm_rf(empty_root) if defined?(empty_root) && empty_root
  end

  test "contributor and viewer can read scan status but cannot trigger" do
    contributor = create_user!(email: "pal@example.test")
    Membership.create!(user: contributor, library: @library, role: Membership::CONTRIBUTOR)
    viewer = create_user!(email: "look@example.test")
    Membership.create!(user: viewer, library: @library, role: Membership::VIEWER)

    post "/api/v1/libraries/#{@library.id}/scan", headers: auth_header(contributor), as: :json
    assert_response :forbidden

    post "/api/v1/libraries/#{@library.id}/scan", headers: auth_header(viewer), as: :json
    assert_response :forbidden

    [contributor, viewer].each do |user|
      get "/api/v1/libraries/#{@library.id}", headers: auth_header(user)
      assert_response :success
      library = response.parsed_body.fetch("library")
      assert_equal "completed", library.dig("scan", "status")
      assert library.dig("scan", "budgets", "max_files").present?
      refute library.key?("cursors")
      refute library.key?("scan_settings")

      get "/api/v1/libraries/#{@library.id}/scan", headers: auth_header(user)
      assert_response :success
      assert_equal "completed", response.parsed_body.dig("scan", "status")
      assert_equal "done", response.parsed_body.dig("last", "phase")
    end
  end
end
