require "test_helper"

class UploaderFilterTest < ActionDispatch::IntegrationTest
  def setup
    @owner = create_owner!
    @friend = create_user!(email: "pal@example.test", display_name: "Pal")
    @viewer = create_user!(email: "viewer@example.test", display_name: "Viewer")
    @outsider = create_user!(email: "outsider@example.test", display_name: "Outsider")
    @library = create_shared_library!(
      owner: @owner,
      contributor: @friend,
      viewer: @viewer,
      name: "Shared pile",
      root_path: "/tmp/uploader-filter"
    )
    Creator.create!(slug: "pack-label", name: "Pack Label", source: Creator::SOURCE_NFS)

    @unowned = @library.vibe_models.create!(folder_name: "nfs-scan", title: "NFS Scan")
    @mine = @library.vibe_models.create!(folder_name: "owner-upload", title: "Owner Upload", uploaded_by: @owner)
    @theirs = @library.vibe_models.create!(folder_name: "friend-upload", title: "Friend Upload", uploaded_by: @friend)
  end

  test "catalog All keeps the shared pile including null attribution" do
    get "/api/v1/models", headers: auth_header(@owner)
    assert_response :success
    ids = catalog_ids
    assert_includes ids, @unowned.id
    assert_includes ids, @mine.id
    assert_includes ids, @theirs.id
    unowned = response.parsed_body.fetch("models").find { |row| row["id"] == @unowned.id }
    assert_nil unowned["uploaded_by"]

    get "/api/v1/models", params: { uploaded_by: "" }, headers: auth_header(@owner)
    assert_response :success
    assert_equal ids.sort, catalog_ids.sort
  end

  test "catalog Me is current_user uploads and excludes null attribution" do
    get "/api/v1/models", params: { uploaded_by: "me" }, headers: auth_header(@owner)
    assert_response :success
    assert_equal [@mine.id], catalog_ids

    get "/api/v1/models", params: { uploaded_by: "me" }, headers: auth_header(@friend)
    assert_response :success
    assert_equal [@theirs.id], catalog_ids

    get "/api/v1/models", params: { uploaded_by: "me" }, headers: auth_header(@viewer)
    assert_response :success
    assert_equal [], catalog_ids
  end

  test "catalog Friend filters by membership user_id and not Creators" do
    get "/api/v1/models", params: { uploaded_by: @friend.id }, headers: auth_header(@owner)
    assert_response :success
    assert_equal [@theirs.id], catalog_ids
    assert_equal @friend.id, response.parsed_body.dig("models", 0, "uploaded_by", "id")
    assert_equal "Pal", response.parsed_body.dig("models", 0, "uploaded_by", "display_name")
  end

  test "catalog unknown or invalid uploaded_by is an empty result not All" do
    get "/api/v1/models", params: { uploaded_by: 9_999_999 }, headers: auth_header(@owner)
    assert_response :success
    assert_equal [], catalog_ids
    refute_includes catalog_ids, @unowned.id

    get "/api/v1/models", params: { uploaded_by: "friend" }, headers: auth_header(@owner)
    assert_response :success
    assert_equal [], catalog_ids

    get "/api/v1/models", params: { uploaded_by: @outsider.id }, headers: auth_header(@owner)
    assert_response :success
    assert_equal [], catalog_ids
  end

  test "search postgres honors the same uploaded_by filter" do
    headers = auth_header(@owner)

    get "/api/v1/search", params: { q: "" }, headers: headers
    assert_response :success
    ids = catalog_ids
    assert_includes ids, @unowned.id
    assert_includes ids, @mine.id
    assert_includes ids, @theirs.id
    assert_equal "postgres", response.parsed_body["engine"]

    get "/api/v1/search", params: { q: "", uploaded_by: "me" }, headers: headers
    assert_response :success
    assert_equal [@mine.id], catalog_ids
    refute_includes catalog_ids, @unowned.id

    get "/api/v1/search", params: { q: "upload", uploaded_by: @friend.id }, headers: headers
    assert_response :success
    assert_equal [@theirs.id], catalog_ids

    get "/api/v1/search", params: { q: "scan", uploaded_by: "me" }, headers: headers
    assert_response :success
    assert_equal [], catalog_ids

    get "/api/v1/search", params: { uploaded_by: 9_999_999 }, headers: headers
    assert_response :success
    assert_equal [], catalog_ids
    assert_equal 0, response.parsed_body["estimated_total"]
  end

  test "library members are memberships not Creators" do
    get "/api/v1/libraries/#{@library.id}/members", headers: auth_header(@viewer)
    assert_response :success
    members = response.parsed_body.fetch("members")
    assert_equal(
      [
        { "id" => @owner.id, "display_name" => @owner.display_name },
        { "id" => @friend.id, "display_name" => "Pal" },
        { "id" => @viewer.id, "display_name" => "Viewer" }
      ],
      members
    )
    refute members.any? { |row| row["display_name"] == "Pack Label" }
    refute members.any? { |row| row["id"] == @outsider.id }
  end

  test "unknown library members is 404" do
    get "/api/v1/libraries/999999/members", headers: auth_header(@owner)
    assert_response :not_found
  end

  private

  def catalog_ids
    response.parsed_body.fetch("models").map { |row| row["id"] }
  end
end
