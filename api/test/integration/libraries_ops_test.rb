require "test_helper"
require "fileutils"
require "zip"

class LibrariesOpsTest < ActionDispatch::IntegrationTest
  def setup
    @root = Rails.root.join("tmp/api-ops-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(@root.join("horn"))
    File.write(@root.join("horn/horn.stl"), "solid x\nendsolid x\n")
    File.write(@root.join("horn/notes.txt"), "signal")
    FileUtils.mkdir_p(@root.join("crate"))
    Zip::File.open(@root.join("crate/parts.zip"), Zip::File::CREATE) do |zip|
      zip.get_output_stream("lid.stl") { |io| io.write("solid lid\nendsolid lid\n") }
      zip.get_output_stream("docs/info.txt") { |io| io.write("lid only") }
    end
    FileUtils.mkdir_p(@root.join("notes-only"))
    File.write(@root.join("notes-only/readme.txt"), "no mesh")

    @password = "secret123"
    @owner = create_owner!(password: @password)
    @library = Library.create!(
      name: "Studio",
      root_path: @root.to_s,
      last_polled_at: Time.utc(2026, 9, 6, 12, 0, 0),
      last_provider: "stub",
      last_error: nil
    )
    Membership.create!(user: @owner, library: @library, role: Membership::OWNER)
    LibraryScanner.new(@library, budget: ScanBudget.unlimited).scan!

    horn = @library.vibe_models.find_by!(folder_name: "horn")
    crate = @library.vibe_models.find_by!(folder_name: "crate")
    notes = @library.vibe_models.find_by!(folder_name: "notes-only")
    horn.update!(cover_status: VibeModel::COVER_PENDING)
    crate.update!(cover_status: VibeModel::COVER_FAILED)
    notes.update!(cover_status: VibeModel::COVER_MISSING)
    Asset.joins(:vibe_model).where(vibe_models: { library_id: @library.id }, kind: "stl").update_all(geometry_digest: nil)
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  test "owner and contributor can read a cheap ops snapshot" do
    contributor = create_user!(email: "pal@example.test")
    Membership.create!(user: contributor, library: @library, role: Membership::CONTRIBUTOR)

    get "/api/v1/libraries/#{@library.id}/ops", headers: auth_header(@owner)
    assert_response :success
    ops = response.parsed_body.fetch("ops")
    assert_equal @library.id, ops["library_id"]
    assert_equal "Studio", ops["library_name"]
    assert_equal "completed", ops.dig("scan", "status")
    assert ops.dig("scan", "budgets", "max_folders").present?
    refute ops["scan"].key?("queue")
    assert_equal %w[max_files max_folders max_seconds], ops.dig("scan", "budgets").keys.sort
    assert_equal "stub", ops.dig("curator", "last_provider")
    assert ops.dig("curator").key?("last_polled_at")
    assert_nil ops.dig("curator", "last_error")
    assert_equal 1, ops.dig("covers", "pending")
    assert_equal 1, ops.dig("covers", "failed")
    assert_equal 1, ops.dig("covers", "missing")
    assert_equal 1, ops.dig("geometry", "assets_missing")
    assert_equal 1, ops.dig("geometry", "archive_members_missing")
    assert_equal "unset", ops.dig("meili", "status")
    refute ops.dig("meili", "configured")

    get "/api/v1/ops", headers: auth_header(contributor)
    assert_response :success
    listed = response.parsed_body.fetch("libraries")
    assert_equal 1, listed.size
    assert_equal ops["library_id"], listed.first["library_id"]
    assert_equal "unset", response.parsed_body.dig("meili", "status")
    assert_equal 1, listed.first.dig("covers", "pending")
  end

  test "viewer cannot read ops but can read scan" do
    viewer = create_user!(email: "look@example.test")
    Membership.create!(user: viewer, library: @library, role: Membership::VIEWER)

    get "/api/v1/libraries/#{@library.id}/ops", headers: auth_header(viewer)
    assert_response :forbidden

    get "/api/v1/ops", headers: auth_header(viewer)
    assert_response :forbidden

    get "/api/v1/libraries/#{@library.id}/scan", headers: auth_header(viewer)
    assert_response :success
    assert_equal "completed", response.parsed_body.dig("scan", "status")
  end

  test "ops reports meili down without walking the library" do
    ENV["MEILI_URL"] = "http://127.0.0.1:9"
    before = @library.vibe_models.count

    get "/api/v1/libraries/#{@library.id}/ops", headers: auth_header(@owner)
    assert_response :success
    meili = response.parsed_body.dig("ops", "meili")
    assert_equal "down", meili["status"]
    assert meili["configured"]
    assert meili["last_error"].present?
    assert_equal before, @library.vibe_models.count
    assert_equal 1, response.parsed_body.dig("ops", "geometry", "assets_missing")

    get "/api/v1/libraries/#{@library.id}/ops", headers: auth_header(@owner)
    assert_response :success
    assert_equal "down", response.parsed_body.dig("ops", "meili", "status")
    assert response.parsed_body.dig("ops", "meili", "last_error").present?
  ensure
    ENV.delete("MEILI_URL")
  end
end
