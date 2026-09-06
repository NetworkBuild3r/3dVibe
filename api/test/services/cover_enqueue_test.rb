require "test_helper"
require "fileutils"

class CoverEnqueueTest < ActiveJob::TestCase
  def setup
    @root = Rails.root.join("tmp/cover-enq-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(@root.join("CreatorPack/model"))
    File.binwrite(@root.join("CreatorPack/model/preview.png"), "png")
    File.write(@root.join("CreatorPack/model/part.stl"), "solid x\nendsolid x\n")
    @library = Library.create!(name: "Covers", root_path: @root.to_s)
    @model = @library.vibe_models.create!(folder_name: "CreatorPack", title: "Creator Pack")
    @preview = @model.assets.create!(
      relative_path: "model/preview.png",
      filename: "preview.png",
      kind: "png",
      mtime: Time.at(1_710_000_000),
      content_digest: "abc123",
      byte_size: 3
    )
    @model.assets.create!(
      relative_path: "model/part.stl",
      filename: "part.stl",
      kind: "stl",
      mtime: Time.at(1_710_000_000),
      content_digest: "def456",
      byte_size: 20
    )
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  test "enqueue sets pending and uses the locked Sidekiq payload" do
    assert_enqueued_with(job: GenerateCoverJob) do
      assert_equal :enqueued, CoverEnqueue.call(@model)
    end
    @model.reload
    assert_equal VibeModel::COVER_PENDING, @model.cover_status
    assert_equal true, @model.cover_placeholder
    assert_equal "#{@preview.id}:1710000000:sha256:abc123", @model.cover_cache_key

    job = enqueued_jobs.find { |item| item["job_class"] == "GenerateCoverJob" }
    payload = job["arguments"].first
    assert_equal @library.id, payload["library_id"]
    assert_equal @model.id, payload["model_id"]
    assert_equal @preview.id, payload["asset_id"]
    assert_equal "CreatorPack/model/preview.png", payload["jailed_path"]
    assert_equal 1_710_000_000, payload["mtime"]
    assert_equal "sha256:abc123", payload["content_hash"]
    assert_equal 512, payload.dig("budget", "max_px")
    assert_equal 250_000, payload.dig("budget", "max_bytes")
  end

  test "same cache key does not re-enqueue while pending or ready" do
    CoverEnqueue.call(@model)
    assert_no_enqueued_jobs only: GenerateCoverJob do
      assert_equal :pending, CoverEnqueue.call(@model.reload)
    end

    CoverWriteback.apply!(
      "model_id" => @model.id,
      "status" => "ready",
      "cover_url" => "/covers/pack.webp",
      "cover_placeholder" => false
    )
    assert_no_enqueued_jobs only: GenerateCoverJob do
      assert_equal :fresh, CoverEnqueue.call(@model.reload)
    end
  end

  test "writeback hook requires cover_url when ready" do
    error = assert_raises(ArgumentError) do
      CoverWriteback.apply!("model_id" => @model.id, "status" => "ready")
    end
    assert_match(/cover_url/, error.message)
  end
end
