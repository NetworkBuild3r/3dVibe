require "test_helper"
require "fileutils"

class CoverPacerTest < ActiveJob::TestCase
  def setup
    @root = Rails.root.join("tmp/cover-pace-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(@root)
    @library = Library.create!(name: "Pace", root_path: @root.to_s)
    CoverPacer.reset!
    @prev = {
      "VIBE_COVER_QUEUE_MAX" => ENV["VIBE_COVER_QUEUE_MAX"],
      "VIBE_COVER_BATCH" => ENV["VIBE_COVER_BATCH"],
      "VIBE_COVER_PACE_SECONDS" => ENV["VIBE_COVER_PACE_SECONDS"]
    }
    ENV["VIBE_COVER_QUEUE_MAX"] = "3"
    ENV["VIBE_COVER_BATCH"] = "2"
    ENV["VIBE_COVER_PACE_SECONDS"] = "0"
  end

  def teardown
    FileUtils.rm_rf(@root)
    CoverPacer.reset!
    @prev.each do |key, value|
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end
  end

  test "enqueue storm only admits a batch and schedules a backlog drain" do
    models = Array.new(6) { |index| create_cover_model("pack-#{index}", named: index.even?) }

    outcomes = models.map { |model| CoverEnqueue.call(model) }
    assert_equal 2, outcomes.count(:enqueued)
    assert_equal 4, outcomes.count(:deferred)

    generate = enqueued_jobs.select { |job| job["job_class"] == "GenerateCoverJob" }
    assert_equal 2, generate.size
    assert generate.size <= 3

    assert enqueued_jobs.any? { |job| job["job_class"] == "CoverBacklogJob" }
    assert models.all? { |model| model.reload.cover_status == VibeModel::COVER_PENDING }
  end

  test "backlog drain prefers named cover candidates over mesh-only" do
    mesh = create_cover_model("mesh-only", named: false, mesh_only: true)
    named = create_cover_model("hero-cover", named: true)
    mesh_asset = mesh.assets.find_by!(kind: "stl")
    cover_asset = named.assets.find_by!(filename: "cover.png")
    mesh.update!(
      cover_status: VibeModel::COVER_PENDING,
      cover_placeholder: true,
      cover_asset_id: mesh_asset.id,
      cover_cache_key: CoverEnqueue.cache_key_for(mesh_asset),
      updated_at: Time.current
    )
    named.update!(
      cover_status: VibeModel::COVER_PENDING,
      cover_placeholder: true,
      cover_asset_id: cover_asset.id,
      cover_cache_key: CoverEnqueue.cache_key_for(cover_asset),
      updated_at: 2.days.ago
    )

    ENV["VIBE_COVER_BATCH"] = "1"
    ENV["VIBE_COVER_QUEUE_MAX"] = "1"
    CoverPacer.reset!

    CoverBacklogJob.perform_now
    generate = enqueued_jobs.select { |job| job["job_class"] == "GenerateCoverJob" }
    assert_equal 1, generate.size
    assert_equal named.id, generate.first["arguments"].first["model_id"]
  end

  test "drain does not enqueue more than queue_max GenerateCoverJobs" do
    5.times { |index| CoverEnqueue.call(create_cover_model("q-#{index}", named: true)) }

    generate = enqueued_jobs.select { |job| job["job_class"] == "GenerateCoverJob" }
    assert generate.size <= 3

    CoverBacklogJob.perform_now
    generate = enqueued_jobs.select { |job| job["job_class"] == "GenerateCoverJob" }
    assert generate.size <= 3
  end

  test "ready without LQIP is backfilled without flipping to pending" do
    model = create_cover_model("needs-lqip", named: true)
    CoverEnqueue.call(model)
    CoverWriteback.apply!(
      "model_id" => model.id,
      "status" => "ready",
      "cover_url" => "/covers/#{model.id}.webp",
      "cover_placeholder" => false,
      "cache_key" => model.reload.cover_cache_key
    )
    CoverPacer.reset!
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    assert_nil model.reload.cover_lqip_url
    assert_equal :lqip_backfill, CoverEnqueue.call(model.reload)
    assert_equal VibeModel::COVER_READY, model.reload.cover_status
    assert enqueued_jobs.any? { |job| job["job_class"] == "GenerateCoverJob" }
  end

  private

  def create_cover_model(folder, named:, mesh_only: false)
    dir = @root.join(folder)
    FileUtils.mkdir_p(dir)
    model = @library.vibe_models.create!(folder_name: folder, title: folder.tr("-", " "))
    unless mesh_only
      name = named ? "cover.png" : "photo.png"
      File.binwrite(dir.join(name), "png")
      model.assets.create!(
        relative_path: name,
        filename: name,
        kind: "png",
        mtime: Time.at(1_710_000_000),
        content_digest: "hash-#{folder}",
        byte_size: 3
      )
    end
    File.write(dir.join("part.stl"), "solid x\nendsolid x\n")
    model.assets.create!(
      relative_path: "part.stl",
      filename: "part.stl",
      kind: "stl",
      mtime: Time.at(1_710_000_000),
      content_digest: "mesh-#{folder}",
      byte_size: 20
    )
    model
  end
end
