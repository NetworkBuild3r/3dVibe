require "test_helper"
require "fileutils"

class DuplicatesTest < ActionDispatch::IntegrationTest
  def setup
    @root = Rails.root.join("tmp/dup-lib-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(@root.join("signal-horn"))
    File.write(@root.join("signal-horn/horn.stl"), "solid horn\nendsolid horn\n")
    FileUtils.mkdir_p(@root.join("horn-copy"))
    File.write(@root.join("horn-copy/horn.stl"), "solid horn\nendsolid horn\n")
    FileUtils.mkdir_p(@root.join("crate"))
    File.write(@root.join("crate/box.stl"), "solid box\nendsolid box\n")
    FileUtils.mkdir_p(@root.join("near-a"))
    File.write(@root.join("near-a/widget.stl"), "solid widget-a\nendsolid widget-a\n")
    FileUtils.mkdir_p(@root.join("near-b"))
    File.write(@root.join("near-b/gizmo.stl"), "solid widget-b-different\nendsolid widget-b-different\n")
    FileUtils.mkdir_p(@root.join("same-name"))
    File.write(@root.join("same-name/notes.txt"), "alpha-notes-same-len!")
    FileUtils.mkdir_p(@root.join("same-name-b"))
    File.write(@root.join("same-name-b/notes.txt"), "beta--notes-same-len!")

    @password = "secret123"
    @owner = create_owner!(password: @password)
    @contributor = create_user!(email: "contrib@example.test")
    @viewer = create_user!(email: "viewer@example.test")
    @library = Library.create!(name: "Dup pile", root_path: @root.to_s)
    Membership.create!(user: @owner, library: @library, role: Membership::OWNER)
    Membership.create!(user: @contributor, library: @library, role: Membership::CONTRIBUTOR)
    Membership.create!(user: @viewer, library: @library, role: Membership::VIEWER)
    LibraryScanner.new(@library, budget: ScanBudget.unlimited).scan!
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  test "analyze creates persisted exact and name_size groups" do
    post "/api/v1/libraries/#{@library.id}/duplicates/analyze",
         headers: auth_header(@owner),
         as: :json
    assert_response :accepted
    assert response.parsed_body["queued"]
    assert_enqueued_with(job: AnalyzeDuplicatesJob, args: [@library.id])

    perform_enqueued_jobs only: AnalyzeDuplicatesJob

    get "/api/v1/duplicates", params: { library_id: @library.id }, headers: auth_header(@owner)
    assert_response :success
    groups = response.parsed_body.fetch("groups")
    horn = groups.find { |group| group["filename"] == "horn.stl" }
    assert horn
    assert_equal "open", horn["status"]
    assert_equal "content_hash", horn["reason"]
    assert_equal "exact", horn["confidence"]
    model_ids = horn.fetch("assets").map { |asset| asset["model_id"] }
    assert_includes model_ids, @library.vibe_models.find_by!(folder_name: "signal-horn").id
    assert_includes model_ids, @library.vibe_models.find_by!(folder_name: "horn-copy").id

    notes = groups.find { |group| group["filename"] == "notes.txt" }
    assert notes
    assert_equal "name_size", notes["reason"]
    assert_equal "likely", notes["confidence"]
  end

  test "geometry_digest groups meshes that are not exact or name_size hits" do
    near_a = @library.vibe_models.find_by!(folder_name: "near-a").assets.find_by!(filename: "widget.stl")
    near_b = @library.vibe_models.find_by!(folder_name: "near-b").assets.find_by!(filename: "gizmo.stl")
    refute_equal near_a.content_digest, near_b.content_digest
    GeometryWriteback.apply!(asset_id: near_a.id, geometry_digest: "mesh:widget-v1")
    GeometryWriteback.apply!(asset_id: near_b.id, geometry_digest: "mesh:widget-v1")

    AnalyzeDuplicatesJob.perform_now(@library.id)

    get "/api/v1/duplicates",
        params: { library_id: @library.id, status: "open" },
        headers: auth_header(@owner)
    groups = response.parsed_body.fetch("groups")
    geo = groups.find { |group| group["reason"] == "geometry" }
    assert geo
    assert_equal "geometry", geo["confidence"]
    assert_equal "mesh:widget-v1", geo["digest"]
    ids = geo.fetch("assets").map { |asset| asset["id"] }
    assert_includes ids, near_a.id
    assert_includes ids, near_b.id
  end

  test "analyze fingerprints re-exports and opens a geometry group" do
    FileUtils.mkdir_p(@root.join("cube-stl"))
    FileUtils.mkdir_p(@root.join("cube-obj"))
    write_ascii_stl(@root.join("cube-stl/part.stl"))
    write_obj(@root.join("cube-obj/part.obj"))
    LibraryScanner.new(@library, budget: ScanBudget.unlimited).scan!

    AnalyzeDuplicatesJob.perform_now(@library.id)

    get "/api/v1/duplicates",
        params: { library_id: @library.id, status: "open" },
        headers: auth_header(@owner)
    geo = response.parsed_body.fetch("groups").find { |group| group["reason"] == "geometry" }
    assert geo
    assert_equal "geometry", geo["confidence"]
    assert geo["digest"].to_s.start_with?("mesh:v1:")
    names = geo.fetch("assets").map { |asset| asset["filename"] }
    assert_includes names, "part.stl"
    assert_includes names, "part.obj"
  end

  test "keep and dismiss record a review and leave terminal groups on re-analyze" do
    AnalyzeDuplicatesJob.perform_now(@library.id)
    horn = DuplicateGroup.open.find_by!(reason: DuplicateGroup::REASON_CONTENT_HASH)
    notes = DuplicateGroup.open.find_by!(reason: DuplicateGroup::REASON_NAME_SIZE)

    post "/api/v1/duplicates/#{horn.id}/keep", headers: auth_header(@contributor), as: :json
    assert_response :success
    assert_equal "kept", response.parsed_body.dig("group", "status")
    assert_equal "keep", response.parsed_body.dig("review", "decision")
    assert horn.reload.duplicate_reviews.exists?(decision: DuplicateReview::KEEP, user: @contributor)

    post "/api/v1/duplicates/#{notes.id}/dismiss",
         params: { payload: { note: "different text" } },
         headers: auth_header(@owner),
         as: :json
    assert_response :success
    assert_equal "dismissed", response.parsed_body.dig("group", "status")
    assert_equal "dismiss", response.parsed_body.dig("review", "decision")

    AnalyzeDuplicatesJob.perform_now(@library.id)
    assert_equal DuplicateGroup::KEPT, horn.reload.status
    assert_equal DuplicateGroup::DISMISSED, notes.reload.status
    assert_equal 0, DuplicateGroup.open.count
  end

  test "merge uses ModelComposer and never deletes files outside the jail" do
    AnalyzeDuplicatesJob.perform_now(@library.id)
    horn = DuplicateGroup.open.find_by!(reason: DuplicateGroup::REASON_CONTENT_HASH)
    source = @library.vibe_models.find_by!(folder_name: "signal-horn")
    target = @library.vibe_models.find_by!(folder_name: "horn-copy")

    post "/api/v1/duplicates/#{horn.id}/merge",
         params: { source_ids: [source.id], target_id: target.id },
         headers: auth_header(@contributor),
         as: :json
    assert_response :success
    assert_equal "merged", response.parsed_body.dig("group", "status")
    assert_equal "merge", response.parsed_body.dig("review", "decision")
    assert File.file?(@root.join("horn-copy/signal-horn/horn.stl"))
    refute File.exist?(@root.join("signal-horn/horn.stl"))
    assert_equal DuplicateGroup::MERGED, horn.reload.status
  end

  test "viewers can list groups but cannot analyze or decide" do
    AnalyzeDuplicatesJob.perform_now(@library.id)
    group = DuplicateGroup.open.find_by!(reason: DuplicateGroup::REASON_CONTENT_HASH)

    get "/api/v1/duplicates", params: { library_id: @library.id }, headers: auth_header(@viewer)
    assert_response :success
    assert response.parsed_body.fetch("groups").any?

    post "/api/v1/libraries/#{@library.id}/duplicates/analyze", headers: auth_header(@viewer), as: :json
    assert_response :forbidden

    post "/api/v1/duplicates/#{group.id}/keep", headers: auth_header(@viewer), as: :json
    assert_response :forbidden
    post "/api/v1/duplicates/#{group.id}/dismiss", headers: auth_header(@viewer), as: :json
    assert_response :forbidden
    post "/api/v1/duplicates/#{group.id}/merge",
         params: { asset_ids: group.assets.pluck(:id) },
         headers: auth_header(@viewer),
         as: :json
    assert_response :forbidden
    assert_equal DuplicateGroup::OPEN, group.reload.status
  end

  test "geometry writeback accepts the shared token or a curator" do
    asset = @library.vibe_models.find_by!(folder_name: "crate").assets.find_by!(filename: "box.stl")

    ENV["VIBE_GEOMETRY_TOKEN"] = "geo-secret"
    post "/api/v1/geometry/writeback",
         params: { asset_id: asset.id, geometry_digest: "mesh:box" },
         headers: { "X-Geometry-Token" => "geo-secret" },
         as: :json
    assert_response :success
    assert_equal "mesh:box", asset.reload.geometry_digest

    post "/api/v1/geometry/writeback",
         params: { asset_id: asset.id, geometry_digest: "mesh:box-2" },
         headers: auth_header(@contributor),
         as: :json
    assert_response :success
    assert_equal "mesh:box-2", asset.reload.geometry_digest

    post "/api/v1/geometry/writeback",
         params: { asset_id: asset.id, geometry_digest: "mesh:nope" },
         headers: auth_header(@viewer),
         as: :json
    assert_response :forbidden
    assert_equal "mesh:box-2", asset.reload.geometry_digest
  ensure
    ENV.delete("VIBE_GEOMETRY_TOKEN")
  end
end
