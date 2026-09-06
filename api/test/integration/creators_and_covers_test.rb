require "test_helper"
require "fileutils"

class CreatorsAndCoversTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  def setup
    @root = Rails.root.join("tmp/creator-cover-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(@root.join("Mz4250 - Dragon Knight"))
    File.write(@root.join("Mz4250 - Dragon Knight/dragon.stl"), "solid d\nendsolid d\n")
    File.binwrite(@root.join("Mz4250 - Dragon Knight/cover.png"), png_bytes)
    FileUtils.mkdir_p(@root.join("Mz4250 - Skeleton"))
    File.write(@root.join("Mz4250 - Skeleton/bones.stl"), "solid b\nendsolid b\n")
    FileUtils.mkdir_p(@root.join("notes-only"))
    File.write(@root.join("notes-only/readme.txt"), "no mesh")

    @password = "secret123"
    @owner = create_owner!(password: @password)
    @library = Library.create!(name: "Studio", root_path: @root.to_s)
    Membership.create!(user: @owner, library: @library, role: Membership::OWNER)
    LibraryScanner.new(@library, budget: ScanBudget.unlimited).scan!
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  test "lists creators and shows by id or slug with paginated models" do
    headers = auth_header(@owner)

    get "/api/v1/creators", headers: headers
    assert_response :success
    slugs = response.parsed_body.fetch("creators").map { |row| row["slug"] }
    assert_includes slugs, "mz4250"
    assert_includes slugs, "notes-only"
    mz = response.parsed_body.fetch("creators").find { |row| row["slug"] == "mz4250" }
    assert_equal "Mz4250", mz["name"]
    assert_equal 2, mz["model_count"]
    assert_equal Creator::SOURCE_NFS, mz["source"]

    get "/api/v1/creators/#{mz['id']}", params: { limit: 1 }, headers: headers
    assert_response :success
    by_id = response.parsed_body
    assert_equal "mz4250", by_id.dig("creator", "slug")
    assert_equal 1, by_id.fetch("models").length
    assert by_id["next_cursor"].present?

    get "/api/v1/creators/mz4250", params: { cursor: by_id["next_cursor"], limit: 1 }, headers: headers
    assert_response :success
    by_slug = response.parsed_body
    assert_equal 1, by_slug.fetch("models").length
    refute_equal by_id["models"].first["id"], by_slug["models"].first["id"]
    titles = (by_id["models"] + by_slug["models"]).map { |model| model["title"] }
    assert titles.any? { |title| title.downcase.include?("dragon") }
    assert titles.any? { |title| title.downcase.include?("skeleton") }
  end

  test "model cards include nullable creator and cover fields" do
    headers = auth_header(@owner)
    dragon = @library.vibe_models.find_by!(folder_name: "Mz4250 - Dragon Knight")

    get "/api/v1/models/#{dragon.id}", headers: headers
    assert_response :success
    card = response.parsed_body.fetch("model")
    assert_equal dragon.creator_id, card.dig("creator", "id")
    assert_equal "mz4250", card.dig("creator", "slug")
    assert_equal "Mz4250", card.dig("creator", "name")
    assert_equal VibeModel::COVER_PENDING, card["cover_status"]
    assert_nil card["cover_url"]
    assert_equal true, card["cover_placeholder"]

    get "/api/v1/models", headers: headers
    assert_response :success
    listed = response.parsed_body.fetch("models").find { |model| model["id"] == dragon.id }
    assert listed["creator"].is_a?(Hash)
    assert listed.key?("cover_status")
    assert listed.key?("cover_url")
    assert listed.key?("cover_placeholder")
  end

  test "scan heuristic upserts one creator from pack prefixes and never invents shelves" do
    dragon = @library.vibe_models.find_by!(folder_name: "Mz4250 - Dragon Knight")
    skeleton = @library.vibe_models.find_by!(folder_name: "Mz4250 - Skeleton")
    notes = @library.vibe_models.find_by!(folder_name: "notes-only")

    assert_equal dragon.creator_id, skeleton.creator_id
    assert_equal "mz4250", dragon.creator.slug
    assert_equal "notes-only", notes.creator.slug
    assert_equal 0, BookmarkFolder.count
    assert_equal 0, Bookmark.count
  end

  test "scan enqueues a budgeted cover job and sets pending" do
    dragon = @library.vibe_models.find_by!(folder_name: "Mz4250 - Dragon Knight")
    cover = dragon.assets.find_by!(filename: "cover.png")
    assert_equal VibeModel::COVER_PENDING, dragon.cover_status
    assert_equal true, dragon.cover_placeholder
    assert_equal CoverEnqueue.cache_key_for(cover), dragon.cover_cache_key

    jobs = enqueued_jobs.select { |job| job["job_class"] == "GenerateCoverJob" }
    payload = jobs.map { |job| job["arguments"].first }.find { |item| item["model_id"] == dragon.id }
    assert payload, "expected GenerateCoverJob for the dragon model"
    assert_equal @library.id, payload["library_id"]
    assert_equal dragon.id, payload["model_id"]
    assert_equal cover.id, payload["asset_id"]
    assert_equal "Mz4250 - Dragon Knight/cover.png", payload["jailed_path"]
    assert_equal cover.mtime.to_i, payload["mtime"]
    assert_equal "sha256:#{cover.content_digest}", payload["content_hash"]
    assert_equal 512, payload.dig("budget", "max_px")
    assert_equal 250_000, payload.dig("budget", "max_bytes")

    notes = @library.vibe_models.find_by!(folder_name: "notes-only")
    assert_equal VibeModel::COVER_MISSING, notes.cover_status
  end

  test "cover writeback sets ready or failed for the rendering worker" do
    headers = auth_header(@owner)
    dragon = @library.vibe_models.find_by!(folder_name: "Mz4250 - Dragon Knight")
    cover = dragon.assets.find_by!(filename: "cover.png")

    post "/api/v1/covers/writeback",
         params: {
           model_id: dragon.id,
           asset_id: cover.id,
           status: "ready",
           cover_url: "/covers/dragon.webp",
           cover_placeholder: false,
           cache_key: dragon.cover_cache_key
         },
         headers: headers,
         as: :json
    assert_response :success
    body = response.parsed_body.fetch("model")
    assert_equal VibeModel::COVER_READY, body["cover_status"]
    assert_equal "/covers/dragon.webp", body["cover_url"]
    assert_equal false, body["cover_placeholder"]
    assert_equal VibeModel::COVER_READY, dragon.reload.cover_status

    post "/api/v1/covers/writeback",
         params: { model_id: dragon.id, status: "failed" },
         headers: headers,
         as: :json
    assert_response :success
    assert_equal VibeModel::COVER_FAILED, dragon.reload.cover_status
    assert_equal true, dragon.cover_placeholder
  end

  test "cover writeback accepts the shared cover token" do
    ENV["VIBE_COVER_TOKEN"] = "cover-secret"
    dragon = @library.vibe_models.find_by!(folder_name: "Mz4250 - Dragon Knight")

    post "/api/v1/covers/writeback",
         params: { model_id: dragon.id, status: "ready", cover_url: "/covers/token.webp" },
         headers: { "X-Cover-Token" => "cover-secret" },
         as: :json
    assert_response :success
    assert_equal "/covers/token.webp", dragon.reload.cover_url
  ensure
    ENV.delete("VIBE_COVER_TOKEN")
  end

  private

  def png_bytes
    ["89504e470d0a1a0a0000000d4948445200000001000000010802000000907753de0000000c4944415478da6360000002000100ffff03000006000557bf2dd40000000049454e44ae426082"].pack("H*")
  end
end
