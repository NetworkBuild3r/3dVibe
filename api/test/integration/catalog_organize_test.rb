require "test_helper"
require "fileutils"

class CatalogOrganizeTest < ActionDispatch::IntegrationTest
  def setup
    @root = Rails.root.join("tmp/organize-lib-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(@root.join("signal-horn"))
    File.write(@root.join("signal-horn/horn.stl"), "solid horn\nendsolid horn\n")
    FileUtils.mkdir_p(@root.join("horn-copy"))
    File.write(@root.join("horn-copy/horn.stl"), "solid horn\nendsolid horn\n")
    FileUtils.mkdir_p(@root.join("crate"))
    File.write(@root.join("crate/box.stl"), "solid box\nendsolid box\n")

    @password = "secret123"
    @owner = create_owner!(password: @password)
    @contributor = create_user!(email: "contrib@example.test")
    @viewer = create_user!(email: "viewer@example.test")
    @library = Library.create!(name: "Organize pile", root_path: @root.to_s)
    Membership.create!(user: @owner, library: @library, role: Membership::OWNER)
    Membership.create!(user: @contributor, library: @library, role: Membership::CONTRIBUTOR)
    Membership.create!(user: @viewer, library: @library, role: Membership::VIEWER)
    LibraryScanner.new(@library).scan!
    @horn = @library.vibe_models.find_by!(folder_name: "signal-horn")
    @copy = @library.vibe_models.find_by!(folder_name: "horn-copy")
    @crate = @library.vibe_models.find_by!(folder_name: "crate")
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  test "contributor can merge and split models via the API" do
    post "/api/v1/models/merge",
         params: { library_id: @library.id, source_ids: [@horn.id], target_id: @crate.id },
         headers: auth_header(@contributor),
         as: :json
    assert_response :created
    target_id = response.parsed_body.dig("model", "id")
    merge_id = response.parsed_body.dig("merge", "id")
    assert File.file?(@root.join("crate/signal-horn/horn.stl"))

    post "/api/v1/models/#{target_id}/split",
         params: { merge_id: merge_id },
         headers: auth_header(@contributor),
         as: :json
    assert_response :success
    names = response.parsed_body.fetch("models").map { |row| row["folder_name"] }
    assert_includes names, "signal-horn"
    assert File.file?(@root.join("signal-horn/horn.stl"))
  end

  test "viewer cannot merge models" do
    post "/api/v1/models/merge",
         params: { library_id: @library.id, source_ids: [@horn.id], target_id: @crate.id },
         headers: auth_header(@viewer),
         as: :json
    assert_response :forbidden
    assert File.file?(@root.join("signal-horn/horn.stl"))
  end

  test "duplicates API groups exact hashes and name-size copies" do
    get "/api/v1/duplicates", params: { library_id: @library.id }, headers: auth_header(@owner)
    assert_response :success
    groups = response.parsed_body.fetch("groups")
    horn_group = groups.find { |group| group["filename"] == "horn.stl" }
    assert horn_group
    assert_equal "exact", horn_group["confidence"]
    model_ids = horn_group.fetch("assets").map { |asset| asset["model_id"] }
    assert_includes model_ids, @horn.id
    assert_includes model_ids, @copy.id
  end
end
