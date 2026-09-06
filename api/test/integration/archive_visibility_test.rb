require "test_helper"
require "fileutils"
require "zip"

class ArchiveVisibilityTest < ActionDispatch::IntegrationTest
  def setup
    @root = Rails.root.join("tmp/archive-api-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(@root.join("packed-minis"))
    Zip::File.open(@root.join("packed-minis/minis.zip"), Zip::File::CREATE) do |zip|
      zip.get_output_stream("hero.stl") { |io| io.write("solid hero\nendsolid hero\n") }
      zip.get_output_stream("preview/hero.png") { |io| io.write(png_bytes) }
      zip.get_output_stream("extras/nested/note.txt") { |io| io.write("deep") }
    end
    @owner = create_owner!
    @library = Library.create!(name: "Studio", root_path: @root.to_s)
    Membership.create!(user: @owner, library: @library, role: Membership::OWNER)
    LibraryScanner.new(@library).scan!
    @model = @library.vibe_models.find_by!(folder_name: "packed-minis")
    @headers = auth_header(@owner)
  end

  def teardown
    FileUtils.rm_rf(@root)
    FileUtils.rm_rf(ArchiveMember.preview_root)
    ENV.delete("VIBE_ARCHIVE_STREAM_BYTES")
  end

  test "archive tree is nested with lazy children and search" do
    get "/api/v1/models/#{@model.id}/archive_members", headers: @headers
    assert_response :success
    body = response.parsed_body
    assert_equal "tree", body["view"]
    paths = body.fetch("members").map { |member| member["internal_path"] }
    assert_includes paths, "hero.stl"
    assert_includes paths, "preview/"
    assert_includes paths, "extras/"
    refute_includes paths, "extras/nested/note.txt"
    assert body["archives"].any? { |archive| archive["filename"] == "minis.zip" && archive["support"] == "full" }

    extras = body.fetch("members").find { |member| member["directory"] && member["name"] == "extras" }
    get "/api/v1/models/#{@model.id}/archive_members",
        params: { asset_id: extras["asset_id"], prefix: extras["path"] },
        headers: @headers
    assert_response :success
    child_names = response.parsed_body.fetch("nodes").map { |node| node["name"] }
    assert_includes child_names, "nested"

    get "/api/v1/models/#{@model.id}/archive_members", params: { q: "hero" }, headers: @headers
    assert_response :success
    search = response.parsed_body
    assert_equal "search", search["view"]
    assert(search.fetch("members").any? { |member| member["internal_path"] == "hero.stl" })
    assert(search.fetch("members").any? { |member| member["image"] && member["internal_path"] == "preview/hero.png" })
  end

  test "member detail and single-entry stream" do
    member = ArchiveMember.joins(:asset).find_by!(internal_path: "hero.stl", assets: { vibe_model_id: @model.id })

    get "/api/v1/archive_members/#{member.id}", headers: @headers
    assert_response :success
    detail = response.parsed_body.fetch("member")
    assert_equal "hero.stl", detail["internal_path"]
    assert_equal "model/stl", detail["content_type"]
    assert detail["mesh"]
    assert detail["streamable"]
    assert_equal "minis.zip", detail["asset_filename"]

    get "/api/v1/archive_members/#{member.id}/content", headers: @headers
    assert_response :success
    assert_includes response.body, "solid hero"
    assert_match(%r{model/stl}, response.media_type)
  end

  test "streams an image preview and refuses a mesh preview" do
    image = ArchiveMember.joins(:asset).find_by!(internal_path: "preview/hero.png", assets: { vibe_model_id: @model.id })
    mesh = ArchiveMember.joins(:asset).find_by!(internal_path: "hero.stl", assets: { vibe_model_id: @model.id })

    get "/api/v1/archive_members/#{image.id}/preview", headers: @headers
    assert_response :success
    assert_equal "image/png", response.media_type
    assert_equal png_bytes, response.body.b

    get "/api/v1/archive_members/#{mesh.id}/preview", headers: @headers
    assert_response :unprocessable_entity
    assert_equal "use_content", response.parsed_body["error"]
  end

  test "search still finds a hero member inside a zip" do
    get "/api/v1/search", params: { q: "hero" }, headers: @headers
    assert_response :success
    titles = response.parsed_body.fetch("models").map { |model| model["title"] }
    assert titles.any? { |title| title.downcase.include?("packed") }
  end

  test "oversized member stream is rejected" do
    ENV["VIBE_ARCHIVE_STREAM_BYTES"] = "4"
    member = ArchiveMember.joins(:asset).find_by!(internal_path: "hero.stl", assets: { vibe_model_id: @model.id })
    get "/api/v1/archive_members/#{member.id}/content", headers: @headers
    assert_response :unprocessable_entity
    assert_match(/oversized/, response.parsed_body["details"].join)
  end

  test "derive preview job caches a hot image member" do
    asset = @model.assets.find_by!(filename: "minis.zip")
    DerivePreviewJob.perform_now(asset.id)
    image = asset.archive_members.find_by!(internal_path: "preview/hero.png")
    assert image.preview_digest.present?
    assert File.file?(image.preview_absolute_path)
  end

  private

  def png_bytes
    ["89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000a49444154789c63000100000500010d0a2db40000000049454e44ae426082"].pack("H*")
  end
end
