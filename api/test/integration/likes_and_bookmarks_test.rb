require "test_helper"
require "fileutils"

class LikesAndBookmarksTest < ActionDispatch::IntegrationTest
  def setup
    @root = Rails.root.join("tmp/likes-lib-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(@root.join("signal-horn"))
    File.write(@root.join("signal-horn/horn.stl"), "solid x\nendsolid x\n")
    FileUtils.mkdir_p(@root.join("crate"))
    File.write(@root.join("crate/box.stl"), "solid y\nendsolid y\n")

    @owner = create_owner!
    @friend = create_user!(email: "friend@example.test")
    @library = Library.create!(name: "Shared pile", root_path: @root.to_s)
    Membership.create!(user: @owner, library: @library, role: Membership::OWNER)
    Membership.create!(user: @friend, library: @library, role: Membership::CONTRIBUTOR)
    LibraryScanner.new(@library).scan!
    @horn = @library.vibe_models.find_by!(folder_name: "signal-horn")
    @crate = @library.vibe_models.find_by!(folder_name: "crate")
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  test "like is personal and does not hide the model from others" do
    post "/api/v1/models/#{@horn.id}/like", headers: auth_header(@owner), as: :json
    assert_response :success
    assert response.parsed_body.dig("model", "liked")
    assert_equal 1, response.parsed_body.dig("model", "like_count")

    get "/api/v1/models/#{@horn.id}", headers: auth_header(@friend)
    assert_response :success
    refute response.parsed_body.dig("model", "liked")
    assert_equal 1, response.parsed_body.dig("model", "like_count")

    get "/api/v1/likes", headers: auth_header(@friend)
    assert_response :success
    assert_empty response.parsed_body.fetch("models")

    get "/api/v1/likes", headers: auth_header(@owner)
    assert_equal [@horn.id], response.parsed_body.fetch("models").map { |row| row["id"] }

    delete "/api/v1/models/#{@horn.id}/like", headers: auth_header(@owner), as: :json
    assert_response :success
    refute response.parsed_body.dig("model", "liked")
    assert_equal 0, response.parsed_body.dig("model", "like_count")
  end

  test "bookmark folders organize the shared catalog for one user" do
    post "/api/v1/bookmark_folders",
         params: { name: "Weekend prints" },
         headers: auth_header(@friend),
         as: :json
    assert_response :created
    folder_id = response.parsed_body.dig("bookmark_folder", "id")

    post "/api/v1/bookmark_folders/#{folder_id}/bookmarks",
         params: { model_id: @crate.id },
         headers: auth_header(@friend),
         as: :json
    assert_response :created
    assert_includes response.parsed_body.dig("model", "bookmark_folder_ids"), folder_id

    get "/api/v1/bookmark_folders/#{folder_id}", headers: auth_header(@friend)
    assert_response :success
    assert_equal [@crate.id], response.parsed_body.dig("bookmark_folder", "models").map { |row| row["id"] }

    get "/api/v1/bookmark_folders", headers: auth_header(@owner)
    assert_response :success
    assert_empty response.parsed_body.fetch("bookmark_folders")

    get "/api/v1/models/#{@crate.id}", headers: auth_header(@owner)
    assert_response :success
    assert_equal @crate.title, response.parsed_body.dig("model", "title")
    assert_empty response.parsed_body.dig("model", "bookmark_folder_ids")

    delete "/api/v1/bookmark_folders/#{folder_id}/bookmarks/#{@crate.id}", headers: auth_header(@friend), as: :json
    assert_response :success
    assert_empty response.parsed_body.dig("model", "bookmark_folder_ids")
  end

  test "cannot bookmark into another user's folder" do
    folder = @owner.bookmark_folders.create!(name: "Mine")
    post "/api/v1/bookmark_folders/#{folder.id}/bookmarks",
         params: { model_id: @horn.id },
         headers: auth_header(@friend),
         as: :json
    assert_response :not_found
  end

  test "folder rename and hard delete leave the catalog intact" do
    post "/api/v1/bookmark_folders",
         params: { name: "Weekend prints" },
         headers: auth_header(@friend),
         as: :json
    assert_response :created
    folder_id = response.parsed_body.dig("bookmark_folder", "id")

    post "/api/v1/bookmark_folders/#{folder_id}/bookmarks",
         params: { model_id: @crate.id },
         headers: auth_header(@friend),
         as: :json
    assert_response :created

    patch "/api/v1/bookmark_folders/#{folder_id}",
          params: { name: "Saturday shelf" },
          headers: auth_header(@friend),
          as: :json
    assert_response :success
    assert_equal "Saturday shelf", response.parsed_body.dig("bookmark_folder", "name")

    patch "/api/v1/bookmark_folders/#{folder_id}",
          params: { name: "   " },
          headers: auth_header(@friend),
          as: :json
    assert_response :unprocessable_entity

    delete "/api/v1/bookmark_folders/#{folder_id}", headers: auth_header(@friend)
    assert_response :no_content

    get "/api/v1/bookmark_folders", headers: auth_header(@friend)
    assert_response :success
    assert_empty response.parsed_body.fetch("bookmark_folders")

    get "/api/v1/models/#{@crate.id}", headers: auth_header(@friend)
    assert_response :success
    assert_equal @crate.title, response.parsed_body.dig("model", "title")
    assert_empty response.parsed_body.dig("model", "bookmark_folder_ids")
  end

  test "cannot rename or delete another user's folder" do
    folder = @owner.bookmark_folders.create!(name: "Mine")

    patch "/api/v1/bookmark_folders/#{folder.id}",
          params: { name: "Stolen" },
          headers: auth_header(@friend),
          as: :json
    assert_response :not_found

    delete "/api/v1/bookmark_folders/#{folder.id}", headers: auth_header(@friend)
    assert_response :not_found
    assert BookmarkFolder.exists?(folder.id)
    assert_equal "Mine", folder.reload.name
  end
end
