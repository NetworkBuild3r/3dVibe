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
    assert row["can_scan"]

    get "/api/v1/libraries/#{@library.id}", headers: auth_header(@owner)
    assert_response :success
    body = response.parsed_body.fetch("library")
    assert_equal "completed", body.dig("scan", "status")
    assert body["scan_settings"]["max_files"].present?
    assert body["cursors"].any? { |cursor| cursor["path_prefix"] == "horn" }
  end

  test "owner can queue an on-demand scan" do
    post "/api/v1/libraries/#{@library.id}/scan", headers: auth_header(@owner), as: :json
    assert_response :accepted
    assert response.parsed_body["queued"]
    assert_equal ScanRun::QUEUED, response.parsed_body.dig("library", "scan", "status")
    assert_enqueued_with(job: IncrementalScanJob, args: [@library.id, nil, @owner.id, ScanRun::TRIGGER_API])
  end

  test "contributor cannot trigger a scan and does not see scan internals" do
    contributor = create_user!(email: "pal@example.test")
    Membership.create!(user: contributor, library: @library, role: Membership::CONTRIBUTOR)

    post "/api/v1/libraries/#{@library.id}/scan", headers: auth_header(contributor), as: :json
    assert_response :forbidden

    get "/api/v1/libraries/#{@library.id}", headers: auth_header(contributor)
    assert_response :success
    refute response.parsed_body.fetch("library").key?("scan")
    refute response.parsed_body.fetch("library").key?("cursors")
  end
end
