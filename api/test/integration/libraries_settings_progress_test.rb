require "test_helper"
require "fileutils"

class LibrariesSettingsProgressTest < ActionDispatch::IntegrationTest
  def setup
    @root = Rails.root.join("tmp/api-settings-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(@root)
    @owner = create_owner!
    @library = Library.create!(
      name: "Studio",
      root_path: @root.to_s,
      layout_mode: Library::LAYOUT_CATEGORY_MODEL
    )
    Membership.create!(user: @owner, library: @library, role: Membership::OWNER)
    @contributor = create_user!(email: "pal@example.test")
    Membership.create!(user: @contributor, library: @library, role: Membership::CONTRIBUTOR)
    @viewer = create_user!(email: "look@example.test")
    Membership.create!(user: @viewer, library: @library, role: Membership::VIEWER)
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  test "authenticated settings GET includes layout_mode" do
    get "/api/v1/libraries/#{@library.id}/settings", headers: auth_header(@owner)
    assert_response :success
    settings = response.parsed_body.fetch("settings")
    assert_equal Library::LAYOUT_CATEGORY_MODEL, settings["layout_mode"]
    assert_equal Library::LAYOUT_CATEGORY_MODEL, settings.dig("scan_settings", "layout_mode")

    get "/api/v1/libraries/#{@library.id}", headers: auth_header(@owner)
    assert_response :success
    body = response.parsed_body.fetch("library")
    assert_equal Library::LAYOUT_CATEGORY_MODEL, body["layout_mode"]
    assert_equal Library::LAYOUT_CATEGORY_MODEL, body.dig("scan_settings", "layout_mode")

    get "/api/v1/libraries/#{@library.id}/settings", headers: auth_header(@contributor)
    assert_response :success
    contrib = response.parsed_body.fetch("settings")
    assert_equal Library::LAYOUT_CATEGORY_MODEL, contrib["layout_mode"]
    refute contrib.key?("scan_settings")
  end

  test "owner PATCH settings updates layout_mode" do
    patch "/api/v1/libraries/#{@library.id}/settings",
          params: { layout_mode: Library::LAYOUT_FLAT },
          headers: auth_header(@owner),
          as: :json
    assert_response :success
    assert_equal Library::LAYOUT_FLAT, response.parsed_body.dig("settings", "layout_mode")
    assert_equal Library::LAYOUT_FLAT, response.parsed_body.dig("library", "layout_mode")
    assert_equal Library::LAYOUT_FLAT, @library.reload.layout_mode

    patch "/api/v1/libraries/#{@library.id}/settings",
          params: { settings: { layout_mode: Library::LAYOUT_CATEGORY_MODEL } },
          headers: auth_header(@owner),
          as: :json
    assert_response :success
    assert_equal Library::LAYOUT_CATEGORY_MODEL, @library.reload.layout_mode
  end

  test "unauthenticated PATCH settings is unauthorized" do
    patch "/api/v1/libraries/#{@library.id}/settings",
          params: { layout_mode: Library::LAYOUT_FLAT },
          as: :json
    assert_response :unauthorized
    assert_equal Library::LAYOUT_CATEGORY_MODEL, @library.reload.layout_mode
  end

  test "contributor and viewer cannot PATCH settings" do
    [@contributor, @viewer].each do |user|
      patch "/api/v1/libraries/#{@library.id}/settings",
            params: { layout_mode: Library::LAYOUT_FLAT },
            headers: auth_header(user),
            as: :json
      assert_response :forbidden
    end
    assert_equal Library::LAYOUT_CATEGORY_MODEL, @library.reload.layout_mode
  end

  test "invalid layout_mode is rejected" do
    patch "/api/v1/libraries/#{@library.id}/settings",
          params: { layout_mode: "nested" },
          headers: auth_header(@owner),
          as: :json
    assert_response :unprocessable_entity
    assert_equal "invalid", response.parsed_body["error"]
    assert_equal Library::LAYOUT_CATEGORY_MODEL, @library.reload.layout_mode
  end

  test "scan and ops JSON increment packs_indexed per admitted pack" do
    run = @library.scan_runs.create!(
      status: ScanRun::RUNNING,
      trigger: ScanRun::TRIGGER_API,
      phase: ScanRun::PHASE_WALK,
      started_at: Time.current,
      folders_indexed: 0
    )

    get "/api/v1/libraries/#{@library.id}/scan", headers: auth_header(@owner)
    assert_response :success
    scan = response.parsed_body.fetch("scan")
    assert_equal 0, scan["packs_indexed"]
    assert_equal true, scan["running"]
    assert_nil scan["last_pack_path"]

    # Stubbed scanner: LibraryScanner increments folders_indexed on each :indexed pack.
    run.update!(folders_indexed: 1, resume_after: "Anime/PackA")
    get "/api/v1/libraries/#{@library.id}/scan", headers: auth_header(@owner)
    assert_response :success
    scan = response.parsed_body.fetch("scan")
    assert_equal 1, scan["packs_indexed"]
    assert_equal 1, scan["folders_indexed"]
    assert_equal "Anime/PackA", scan["last_pack_path"]
    assert_equal true, scan["running"]

    run.update!(folders_indexed: 2, resume_after: "Anime/PackB")
    get "/api/v1/libraries/#{@library.id}/ops", headers: auth_header(@owner)
    assert_response :success
    ops_scan = response.parsed_body.dig("ops", "scan")
    assert_equal 2, ops_scan["packs_indexed"]
    assert_equal "Anime/PackB", ops_scan["last_pack_path"]
    assert_equal true, ops_scan["running"]
    refute_includes ops_scan["last_pack_path"].to_s, @root.to_s
  end

  test "last_pack_path omits jail escapes" do
    @library.scan_runs.create!(
      status: ScanRun::RUNNING,
      trigger: ScanRun::TRIGGER_API,
      phase: ScanRun::PHASE_WALK,
      started_at: Time.current,
      folders_indexed: 1,
      resume_after: "../etc"
    )

    get "/api/v1/libraries/#{@library.id}/scan", headers: auth_header(@owner)
    assert_response :success
    scan = response.parsed_body.fetch("scan")
    assert_nil scan["last_pack_path"]
    assert_nil scan["resume_after"]
    assert_nil scan.dig("resume", "resume_after")
    refute_includes response.body, "/etc"
    refute_includes response.body, ".."
  end

  test "GET models includes category after one pack without a mega-category row" do
    @library.vibe_models.create!(folder_name: "Anime/PackA", title: "Packa")

    get "/api/v1/models", params: { library_id: @library.id }, headers: auth_header(@owner)
    assert_response :success
    models = response.parsed_body.fetch("models")
    assert_equal 1, models.length
    card = models.first
    assert_equal "Anime", card["category"]
    assert_equal "Anime/PackA", card["folder_name"]
    refute(models.any? { |model| model["folder_name"] == "Anime" })
    refute(models.any? { |model| model["title"] == "Anime" })
  end
end
