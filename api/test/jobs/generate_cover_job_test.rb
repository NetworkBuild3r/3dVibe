require "test_helper"
require "fileutils"
require "vips"

class GenerateCoverJobTest < ActionDispatch::IntegrationTest
  def setup
    @root = Rails.root.join("tmp/cover-gen-#{SecureRandom.hex(4)}")
    @cover_root = Rails.root.join("tmp/covers-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(@root.join("CreatorPack/model"))
    FileUtils.mkdir_p(@cover_root)
    ENV["VIBE_COVER_ROOT"] = @cover_root.to_s

    write_png(@root.join("CreatorPack/model/preview.png"), 64, 48)
    File.write(@root.join("CreatorPack/model/part.stl"), "solid x\nendsolid x\n")

    @library = Library.create!(name: "Cover gen", root_path: @root.to_s)
    @model = @library.vibe_models.create!(
      folder_name: "CreatorPack",
      title: "Creator Pack",
      cover_status: VibeModel::COVER_PENDING,
      cover_placeholder: true
    )
    @preview = @model.assets.create!(
      relative_path: "model/preview.png",
      filename: "preview.png",
      kind: "png",
      mtime: Time.at(1_710_000_000),
      content_digest: "abc123",
      byte_size: File.size(@root.join("CreatorPack/model/preview.png"))
    )
    @mesh = @model.assets.create!(
      relative_path: "model/part.stl",
      filename: "part.stl",
      kind: "stl",
      mtime: Time.at(1_710_000_000),
      content_digest: "def456",
      byte_size: 20
    )
    @model.update!(cover_cache_key: CoverEnqueue.cache_key_for(@preview), cover_asset_id: @preview.id)
  end

  def teardown
    FileUtils.rm_rf(@root)
    FileUtils.rm_rf(@cover_root)
    ENV.delete("VIBE_COVER_ROOT")
  end

  test "happy path writes back ready with a cover file" do
    GenerateCoverJob.perform_now(image_payload)

    @model.reload
    assert_equal VibeModel::COVER_READY, @model.cover_status
    assert_equal false, @model.cover_placeholder
    assert_equal "/covers/#{@model.id}.webp", @model.cover_url
    assert_equal "#{@preview.id}:1710000000:sha256:abc123", @model.cover_cache_key
    assert_equal @preview.id, @model.cover_asset_id

    dest = @cover_root.join("#{@model.id}.webp")
    assert File.file?(dest), "expected generated cover at #{dest}"
    image = Vips::Image.new_from_file(dest.to_s)
    assert image.width <= 512
    assert image.height <= 512
    assert File.size(dest) <= 250_000
  end

  test "budget clamp limits pixels and bytes" do
    write_png(@root.join("CreatorPack/model/huge.png"), 1600, 1200)
    huge = @model.assets.create!(
      relative_path: "model/huge.png",
      filename: "huge.png",
      kind: "png",
      mtime: Time.at(1_710_000_001),
      content_digest: "huge123",
      byte_size: File.size(@root.join("CreatorPack/model/huge.png"))
    )
    payload = image_payload.merge(
      "asset_id" => huge.id,
      "jailed_path" => "CreatorPack/model/huge.png",
      "mtime" => 1_710_000_001,
      "content_hash" => "sha256:huge123",
      "budget" => { "max_px" => 64, "max_bytes" => 8_000 }
    )

    GenerateCoverJob.perform_now(payload)

    @model.reload
    assert_equal VibeModel::COVER_READY, @model.cover_status
    dest = @cover_root.join("#{@model.id}.webp")
    assert File.file?(dest)
    image = Vips::Image.new_from_file(dest.to_s)
    assert image.width <= 64, "width #{image.width} exceeded max_px"
    assert image.height <= 64, "height #{image.height} exceeded max_px"
    assert File.size(dest) <= 8_000, "bytes #{File.size(dest)} exceeded max_bytes"
  end

  test "jail refusal writes back failed" do
    GenerateCoverJob.perform_now(image_payload.merge("jailed_path" => "../etc/passwd"))

    @model.reload
    assert_equal VibeModel::COVER_FAILED, @model.cover_status
    assert_equal true, @model.cover_placeholder
    assert_nil @model.cover_url
    refute File.file?(@cover_root.join("#{@model.id}.webp"))
  end

  test "mesh without preview writes back failed" do
    FileUtils.rm_f(@root.join("CreatorPack/model/preview.png"))
    GenerateCoverJob.perform_now(mesh_payload)

    @model.reload
    assert_equal VibeModel::COVER_FAILED, @model.cover_status
    assert_equal true, @model.cover_placeholder
    assert_nil @model.cover_url
    refute File.file?(@cover_root.join("#{@model.id}.webp"))
  end

  test "mesh uses a preview sibling under the jail" do
    GenerateCoverJob.perform_now(mesh_payload)

    @model.reload
    assert_equal VibeModel::COVER_READY, @model.cover_status
    assert_equal "/covers/#{@model.id}.webp", @model.cover_url
    assert File.file?(@cover_root.join("#{@model.id}.webp"))
  end

  test "cache key skip does not regenerate a ready cover" do
    GenerateCoverJob.perform_now(image_payload)
    dest = @cover_root.join("#{@model.id}.webp")
    url = @model.reload.cover_url
    old_mtime = Time.at(1_600_000_000)
    File.utime(old_mtime, old_mtime, dest)

    assert_equal :fresh, GenerateCoverJob.perform_now(image_payload)
    @model.reload
    assert_equal VibeModel::COVER_READY, @model.cover_status
    assert_equal url, @model.cover_url
    assert_equal old_mtime.to_i, File.mtime(dest).to_i
  end

  test "generated cover is served at the write-back url" do
    GenerateCoverJob.perform_now(image_payload)
    get "/covers/#{@model.id}.webp"
    assert_response :success
    assert_equal "image/webp", response.media_type
    assert response.body.bytesize.positive?
  end

  private

  def image_payload
    {
      "library_id" => @library.id,
      "model_id" => @model.id,
      "asset_id" => @preview.id,
      "jailed_path" => "CreatorPack/model/preview.png",
      "mtime" => 1_710_000_000,
      "content_hash" => "sha256:abc123",
      "budget" => { "max_px" => 512, "max_bytes" => 250_000 }
    }
  end

  def mesh_payload
    {
      "library_id" => @library.id,
      "model_id" => @model.id,
      "asset_id" => @mesh.id,
      "jailed_path" => "CreatorPack/model/part.stl",
      "mtime" => 1_710_000_000,
      "content_hash" => "sha256:def456",
      "budget" => { "max_px" => 512, "max_bytes" => 250_000 }
    }
  end

  def write_png(path, width, height)
    Vips::Image.black(width, height, bands: 3).write_to_file(path.to_s)
  end
end
