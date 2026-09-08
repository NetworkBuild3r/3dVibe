require "test_helper"
require "fileutils"

class CatalogRebuildJobTest < ActiveJob::TestCase
  def setup
    @root = Rails.root.join("tmp/rebuild-job-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(@root.join("Anime/PackA"))
    File.write(@root.join("Anime/PackA/hero.stl"), "solid x\nendsolid x\n")
    @owner = create_owner!
    @contributor = create_user!(email: "contrib-rebuild@example.test")
    @library = create_shared_library!(
      owner: @owner,
      contributor: @contributor,
      name: "Rebuild jobs",
      root_path: @root.to_s,
      layout_mode: Library::LAYOUT_CATEGORY_MODEL
    )
    @mega = @library.vibe_models.create!(folder_name: "Anime", title: "Anime")
    @mega.assets.create!(relative_path: "PackA/hero.stl", filename: "hero.stl", kind: "stl")
  end

  def teardown
    FileUtils.rm_rf(@root) if defined?(@root) && @root
  end

  test "enqueues on the isolated scan queue" do
    assert_enqueued_with(job: CatalogRebuildJob, queue: ScanSettings.queue) do
      CatalogRebuildJob.perform_later(@library.id, false, CatalogRebuild::WIPE_MEGA, @owner.id)
    end
  end

  test "dry-run perform_now reports without deleting or enqueueing a scan" do
    report = CatalogRebuildJob.perform_now(@library.id, false, CatalogRebuild::WIPE_MEGA, @owner.id)
    assert_equal [@mega.id], report[:models].map { |row| row[:id] }
    assert_equal false, report[:scan_enqueued]
    assert VibeModel.exists?(@mega.id)
    assert File.exist?(@root.join("Anime/PackA/hero.stl"))
    assert_no_enqueued_jobs only: IncrementalScanJob
  end

  test "apply perform_now as owner deletes mega-model, keeps files, enqueues IncrementalScanJob" do
    assert_enqueued_with(job: IncrementalScanJob, queue: ScanSettings.queue) do
      CatalogRebuildJob.perform_now(@library.id, true, CatalogRebuild::WIPE_MEGA, @owner.id)
    end
    refute VibeModel.exists?(@mega.id)
    assert File.exist?(@root.join("Anime/PackA/hero.stl"))
  end

  test "apply perform_now as contributor is forbidden" do
    assert_raises(CatalogRebuild::Forbidden) do
      CatalogRebuildJob.perform_now(@library.id, true, CatalogRebuild::WIPE_MEGA, @contributor.id)
    end
    assert VibeModel.exists?(@mega.id)
    assert File.exist?(@root.join("Anime/PackA/hero.stl"))
  end
end
