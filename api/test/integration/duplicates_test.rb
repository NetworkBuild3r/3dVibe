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

  test "extract copies an archive member onto disk then merge accepts the new asset" do
    member = seed_packed_member!
    loose = @library.vibe_models.find_by!(folder_name: "crate").assets.find_by!(filename: "box.stl")
    GeometryWriteback.apply!(archive_member_id: member.id, geometry_digest: "mesh:v1:extract")
    GeometryWriteback.apply!(asset_id: loose.id, geometry_digest: "mesh:v1:extract")
    AnalyzeDuplicatesJob.perform_now(@library.id)
    group = DuplicateGroup.open.find_by!(reason: DuplicateGroup::REASON_GEOMETRY, digest: "mesh:v1:extract")
    zip_bytes = File.binread(@root.join("packed/pack.zip"))

    post "/api/v1/duplicates/#{group.id}/extract",
         params: { archive_member_ids: [member.id], title: "From pack" },
         headers: auth_header(@contributor),
         as: :json
    assert_response :created
    extracted = response.parsed_body.fetch("extracted")
    assert_equal 1, extracted.size
    assert_equal true, extracted.first["mergeable"]
    assert_equal member.id, extracted.first["archive_member_id"]
    asset_id = extracted.first["asset_id"]
    folder = response.parsed_body.dig("model", "folder_name")
    assert File.file?(@root.join("#{folder}/foo.stl"))
    refute File.exist?(@root.join("packed/path/foo.stl"))
    assert_equal zip_bytes, File.binread(@root.join("packed/pack.zip"))
    assert_equal DuplicateGroup::OPEN, group.reload.status

    get "/api/v1/duplicates", params: { library_id: @library.id, status: "open" }, headers: auth_header(@owner)
    packed = response.parsed_body.fetch("groups").find { |row| row["id"] == group.id }
      .fetch("members").find { |row| row["kind"] == "archive_member" }
    assert_equal false, packed["mergeable"]

    post "/api/v1/duplicates/#{group.id}/merge",
         params: { asset_ids: [asset_id], target_id: loose.vibe_model_id },
         headers: auth_header(@contributor),
         as: :json
    assert_response :success
    assert_equal "merged", response.parsed_body.dig("group", "status")
    assert File.file?(@root.join("crate/#{folder}/foo.stl"))
  end

  test "extract_and_merge streams the member then merges loose assets" do
    member = seed_packed_member!
    loose = @library.vibe_models.find_by!(folder_name: "crate").assets.find_by!(filename: "box.stl")
    GeometryWriteback.apply!(archive_member_id: member.id, geometry_digest: "mesh:v1:compound")
    GeometryWriteback.apply!(asset_id: loose.id, geometry_digest: "mesh:v1:compound")
    AnalyzeDuplicatesJob.perform_now(@library.id)
    group = DuplicateGroup.open.find_by!(reason: DuplicateGroup::REASON_GEOMETRY, digest: "mesh:v1:compound")

    post "/api/v1/duplicates/#{group.id}/extract_and_merge",
         params: { archive_member_ids: [member.id], target_id: loose.vibe_model_id, title: "Crate kit" },
         headers: auth_header(@contributor),
         as: :json
    assert_response :created
    assert_equal true, response.parsed_body.fetch("extracted").first["mergeable"]
    assert_equal "merged", response.parsed_body.dig("group", "status")
    assert_equal "merge", response.parsed_body.dig("review", "decision")
    assert File.file?(@root.join("crate/foo.stl"))
    assert File.file?(@root.join("crate/box.stl"))
    refute File.exist?(@root.join("packed/path/foo.stl"))
    assert File.file?(@root.join("packed/pack.zip"))
    assert_equal DuplicateGroup::MERGED, group.reload.status
    assert_equal "Crate kit", @library.vibe_models.find(loose.vibe_model_id).title
  end

  test "extract rejects a jail-escaping folder and viewers cannot extract" do
    member = seed_packed_member!
    loose = @library.vibe_models.find_by!(folder_name: "crate").assets.find_by!(filename: "box.stl")
    GeometryWriteback.apply!(archive_member_id: member.id, geometry_digest: "mesh:v1:jail")
    GeometryWriteback.apply!(asset_id: loose.id, geometry_digest: "mesh:v1:jail")
    AnalyzeDuplicatesJob.perform_now(@library.id)
    group = DuplicateGroup.open.find_by!(reason: DuplicateGroup::REASON_GEOMETRY, digest: "mesh:v1:jail")

    post "/api/v1/duplicates/#{group.id}/extract",
         params: { archive_member_ids: [member.id], folder_name: "../etc" },
         headers: auth_header(@owner),
         as: :json
    assert_response :unprocessable_entity
    refute File.exist?(Pathname.new(@root).join("..", "etc"))
    assert File.file?(@root.join("packed/pack.zip"))

    post "/api/v1/duplicates/#{group.id}/extract",
         params: { archive_member_ids: [member.id], title: "Nope" },
         headers: auth_header(@viewer),
         as: :json
    assert_response :forbidden
    post "/api/v1/duplicates/#{group.id}/extract_and_merge",
         params: { archive_member_ids: [member.id], target_id: loose.vibe_model_id },
         headers: auth_header(@viewer),
         as: :json
    assert_response :forbidden
    assert_equal DuplicateGroup::OPEN, group.reload.status
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

  test "geometry writeback sets archive_member.geometry_digest" do
    member = seed_packed_member!

    ENV["VIBE_GEOMETRY_TOKEN"] = "geo-secret"
    post "/api/v1/geometry/writeback",
         params: { archive_member_id: member.id, geometry_digest: "mesh:v1:packed" },
         headers: { "X-Geometry-Token" => "geo-secret" },
         as: :json
    assert_response :success
    assert_equal "mesh:v1:packed", member.reload.geometry_digest
    assert_equal member.id, response.parsed_body.dig("archive_member", "archive_member_id")
    assert_equal "pack.zip → path/foo.stl", response.parsed_body.dig("archive_member", "archive_path")

    post "/api/v1/geometry/writeback",
         params: { archive_member_id: member.id, geometry_digest: "mesh:v1:packed-2" },
         headers: auth_header(@contributor),
         as: :json
    assert_response :success
    assert_equal "mesh:v1:packed-2", member.reload.geometry_digest

    post "/api/v1/geometry/writeback",
         params: { archive_member_id: member.id, geometry_digest: "mesh:v1:nope" },
         headers: auth_header(@viewer),
         as: :json
    assert_response :forbidden
    assert_equal "mesh:v1:packed-2", member.reload.geometry_digest
  ensure
    ENV.delete("VIBE_GEOMETRY_TOKEN")
  end

  test "analyze clusters a loose asset and archive member on the same geometry digest" do
    member = seed_packed_member!
    loose = @library.vibe_models.find_by!(folder_name: "crate").assets.find_by!(filename: "box.stl")
    GeometryWriteback.apply!(archive_member_id: member.id, geometry_digest: "mesh:v1:shared")
    GeometryWriteback.apply!(asset_id: loose.id, geometry_digest: "mesh:v1:shared")

    AnalyzeDuplicatesJob.perform_now(@library.id)

    get "/api/v1/duplicates",
        params: { library_id: @library.id, status: "open" },
        headers: auth_header(@owner)
    assert_response :success
    geo = response.parsed_body.fetch("groups").find { |group| group["reason"] == "geometry" && group["digest"] == "mesh:v1:shared" }
    assert geo
    assert_equal "geometry", geo["confidence"]
    kinds = geo.fetch("members").map { |row| row["kind"] }
    assert_includes kinds, "asset"
    assert_includes kinds, "archive_member"
    packed = geo.fetch("members").find { |row| row["kind"] == "archive_member" }
    assert_equal member.id, packed["archive_member_id"]
    assert_equal "path/foo.stl", packed["member_path"]
    assert_equal "pack.zip → path/foo.stl", packed["archive_path"]
    assert_equal false, packed["mergeable"]
    assert_equal member.asset_id, packed["parent_asset_id"]
    assert_equal "pack.zip", packed["parent_filename"]
    loose_row = geo.fetch("members").find { |row| row["kind"] == "asset" }
    assert_equal loose.id, loose_row["asset_id"]
    assert_equal true, loose_row["mergeable"]
  end

  test "merge returns merge_unsupported when an archive member is selected" do
    member = seed_packed_member!
    loose = @library.vibe_models.find_by!(folder_name: "crate").assets.find_by!(filename: "box.stl")
    GeometryWriteback.apply!(archive_member_id: member.id, geometry_digest: "mesh:v1:merge-block")
    GeometryWriteback.apply!(asset_id: loose.id, geometry_digest: "mesh:v1:merge-block")
    AnalyzeDuplicatesJob.perform_now(@library.id)
    group = DuplicateGroup.open.find_by!(reason: DuplicateGroup::REASON_GEOMETRY, digest: "mesh:v1:merge-block")
    target = loose.vibe_model

    post "/api/v1/duplicates/#{group.id}/merge",
         params: { archive_member_ids: [member.id], target_id: target.id },
         headers: auth_header(@contributor),
         as: :json
    assert_response :unprocessable_entity
    assert_equal "merge_unsupported", response.parsed_body["error"]
    assert_match(/archive-resident/i, response.parsed_body["message"])
    assert_equal DuplicateGroup::OPEN, group.reload.status
    refute group.duplicate_reviews.exists?
  end

  test "keep and dismiss still work on groups that include an archive member" do
    member = seed_packed_member!
    loose = @library.vibe_models.find_by!(folder_name: "crate").assets.find_by!(filename: "box.stl")
    GeometryWriteback.apply!(archive_member_id: member.id, geometry_digest: "mesh:v1:hitl")
    GeometryWriteback.apply!(asset_id: loose.id, geometry_digest: "mesh:v1:hitl")
    AnalyzeDuplicatesJob.perform_now(@library.id)
    group = DuplicateGroup.open.find_by!(reason: DuplicateGroup::REASON_GEOMETRY, digest: "mesh:v1:hitl")

    post "/api/v1/duplicates/#{group.id}/keep", headers: auth_header(@contributor), as: :json
    assert_response :success
    assert_equal "kept", response.parsed_body.dig("group", "status")
    assert_equal "keep", response.parsed_body.dig("review", "decision")
    assert_equal DuplicateGroup::KEPT, group.reload.status

    other = seed_second_packed_member!
    GeometryWriteback.apply!(archive_member_id: other.id, geometry_digest: "mesh:v1:hitl-b")
    GeometryWriteback.apply!(asset_id: loose.id, geometry_digest: "mesh:v1:hitl-b")
    AnalyzeDuplicatesJob.perform_now(@library.id)
    dismissable = DuplicateGroup.open.find_by!(reason: DuplicateGroup::REASON_GEOMETRY, digest: "mesh:v1:hitl-b")

    post "/api/v1/duplicates/#{dismissable.id}/dismiss", headers: auth_header(@owner), as: :json
    assert_response :success
    assert_equal "dismissed", response.parsed_body.dig("group", "status")
    assert_equal DuplicateGroup::DISMISSED, dismissable.reload.status

    AnalyzeDuplicatesJob.perform_now(@library.id)
    assert_equal DuplicateGroup::KEPT, group.reload.status
    assert_equal DuplicateGroup::DISMISSED, dismissable.reload.status
  end

  test "analyze fingerprints a packed mesh and clusters it with the same loose file" do
    member = seed_cube_packed_member!
    loose = seed_cube_loose!

    AnalyzeDuplicatesJob.perform_now(@library.id)

    assert_match(/\Amesh:v1:[0-9a-f]{64}\z/, member.reload.geometry_digest)
    assert_equal member.geometry_digest, loose.reload.geometry_digest
    refute File.exist?(@root.join("packed-cube/path/foo.stl"))
    assert File.file?(@root.join("packed-cube/pack.zip"))

    get "/api/v1/duplicates",
        params: { library_id: @library.id, status: "open" },
        headers: auth_header(@owner)
    assert_response :success
    geo = response.parsed_body.fetch("groups").find { |group| group["reason"] == "geometry" && group["digest"] == member.geometry_digest }
    assert geo
    kinds = geo.fetch("members").map { |row| row["kind"] }
    assert_includes kinds, "asset"
    assert_includes kinds, "archive_member"
  end

  test "analyze enqueues leftover archive member geometry jobs without extracting the zip" do
    member = seed_packed_member!
    assert_nil member.geometry_digest

    assert_enqueued_with(job: ComputeArchiveMemberGeometryDigestJob, args: [member.id]) do
      AnalyzeDuplicatesJob.perform_now(@library.id)
    end
    assert_nil member.reload.geometry_digest
    assert File.file?(@root.join("packed/pack.zip"))
    refute File.exist?(@root.join("packed/path/foo.stl"))

    ComputeArchiveMemberGeometryDigestJob.perform_now(member.id)
    assert_nil member.reload.geometry_digest
    refute File.exist?(@root.join("packed/path/foo.stl"))
  end

  private

  def seed_packed_member!
    require "zip"
    FileUtils.mkdir_p(@root.join("packed"))
    Zip::File.open(@root.join("packed/pack.zip"), Zip::File::CREATE) do |zip|
      zip.get_output_stream("path/foo.stl") { |io| io.write("solid foo\nendsolid foo\n") }
    end
    LibraryScanner.new(@library, budget: ScanBudget.unlimited).scan!
    archive = @library.vibe_models.find_by!(folder_name: "packed").assets.find_by!(filename: "pack.zip")
    archive.archive_members.find_by!(internal_path: "path/foo.stl")
  end

  def seed_cube_loose!
    FileUtils.mkdir_p(@root.join("loose-cube"))
    write_ascii_stl(@root.join("loose-cube/box.stl"), CUBE_FACES, name: "box")
    LibraryScanner.new(@library, budget: ScanBudget.unlimited).scan!
    @library.vibe_models.find_by!(folder_name: "loose-cube").assets.find_by!(filename: "box.stl")
  end

  def seed_cube_packed_member!
    require "zip"
    FileUtils.mkdir_p(@root.join("packed-cube"))
    stl = Tempfile.new(["cube", ".stl"])
    write_ascii_stl(stl.path, CUBE_FACES, name: "box")
    Zip::File.open(@root.join("packed-cube/pack.zip"), Zip::File::CREATE) do |zip|
      zip.get_output_stream("path/foo.stl") { |io| io.write(File.binread(stl.path)) }
    end
    LibraryScanner.new(@library, budget: ScanBudget.unlimited).scan!
    archive = @library.vibe_models.find_by!(folder_name: "packed-cube").assets.find_by!(filename: "pack.zip")
    archive.archive_members.find_by!(internal_path: "path/foo.stl")
  ensure
    stl&.close!
  end

  def seed_second_packed_member!
    require "zip"
    FileUtils.mkdir_p(@root.join("packed-b"))
    Zip::File.open(@root.join("packed-b/other.zip"), Zip::File::CREATE) do |zip|
      zip.get_output_stream("inner/bar.stl") { |io| io.write("solid bar\nendsolid bar\n") }
    end
    LibraryScanner.new(@library, budget: ScanBudget.unlimited).scan!
    archive = @library.vibe_models.find_by!(folder_name: "packed-b").assets.find_by!(filename: "other.zip")
    archive.archive_members.find_by!(internal_path: "inner/bar.stl")
  end
end
