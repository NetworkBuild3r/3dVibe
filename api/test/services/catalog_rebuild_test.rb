require "test_helper"
require "fileutils"
require "rake"

class CatalogRebuildTest < ActiveJob::TestCase
  def setup
    @root = Rails.root.join("tmp/rebuild-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(@root.join("Anime/PackA"))
    File.write(@root.join("Anime/PackA/hero.stl"), "solid x\nendsolid x\n")
    @owner = create_owner!
    @viewer = create_user!(email: "viewer-rebuild@example.test")
    @library = create_shared_library!(
      owner: @owner,
      viewer: @viewer,
      name: "Rebuild pile",
      root_path: @root.to_s,
      layout_mode: Library::LAYOUT_CATEGORY_MODEL
    )
    @mega = @library.vibe_models.create!(folder_name: "Anime", title: "Anime mega")
    @mega.assets.create!(relative_path: "PackA/hero.stl", filename: "hero.stl", kind: "stl")
    @pack = @library.vibe_models.create!(folder_name: "Anime/PackA", title: "Pack A")
    @library.scan_cursors.create!(path_prefix: "Anime")
    @library.scan_cursors.create!(path_prefix: "Anime/PackA")
    Rails.application.load_tasks unless Rake::Task.task_defined?("vibe:rebuild_catalog")
    reset_rebuild_env!
  end

  def teardown
    reset_rebuild_env!
    FileUtils.rm_rf(@root) if defined?(@root) && @root
  end

  test "dry-run reports mega-model ids without deleting rows or files" do
    report = CatalogRebuild.new(@library, apply: false, actor: @owner).call

    assert_equal false, report[:apply]
    assert_equal CatalogRebuild::WIPE_MEGA, report[:wipe]
    assert_equal 0, report[:deleted]
    assert_equal false, report[:scan_enqueued]
    assert_equal 0, report[:files_unlinked]
    assert_equal 1, report[:models].size
    assert_equal @mega.id, report[:models].first[:id]
    assert_equal "Anime", report[:models].first[:folder_name]
    assert_equal "Anime mega", report[:models].first[:title]
    assert VibeModel.exists?(@mega.id)
    assert VibeModel.exists?(@pack.id)
    assert File.exist?(@root.join("Anime/PackA/hero.stl"))
    assert_no_enqueued_jobs only: IncrementalScanJob
  end

  test "apply as owner wipes first-level mega-models, keeps pack rows, leaves files, enqueues scan" do
    assert_enqueued_with(
      job: IncrementalScanJob,
      args: [@library.id, nil, @owner.id, ScanRun::TRIGGER_REBUILD],
      queue: ScanSettings.queue
    ) do
      report = CatalogRebuild.new(@library, apply: true, actor: @owner).call
      assert_equal true, report[:apply]
      assert_equal 1, report[:deleted]
      assert_equal true, report[:scan_enqueued]
      assert_equal 0, report[:files_unlinked]
    end

    refute VibeModel.exists?(@mega.id)
    assert VibeModel.exists?(@pack.id)
    assert_equal 0, Asset.where(vibe_model_id: @mega.id).count
    assert File.exist?(@root.join("Anime/PackA/hero.stl"))
    refute @library.scan_cursors.exists?(path_prefix: "Anime")
    assert @library.scan_cursors.exists?(path_prefix: "Anime/PackA")
  end

  test "documented wipe=all deletes every catalog row then enqueues scan; files remain" do
    CatalogRebuild.new(@library, apply: true, wipe: CatalogRebuild::WIPE_ALL, actor: @owner).call

    assert_equal 0, @library.vibe_models.count
    assert File.exist?(@root.join("Anime/PackA/hero.stl"))
    assert_enqueued_with(job: IncrementalScanJob, queue: ScanSettings.queue)
    assert_equal 0, @library.scan_cursors.count
  end

  test "non-owner cannot apply and files stay" do
    assert_raises(CatalogRebuild::Forbidden) do
      CatalogRebuild.new(@library, apply: true, actor: @viewer).call
    end
    assert VibeModel.exists?(@mega.id)
    assert File.exist?(@root.join("Anime/PackA/hero.stl"))
    assert_no_enqueued_jobs only: IncrementalScanJob
  end

  test "apply without actor is forbidden" do
    assert_raises(CatalogRebuild::Forbidden) do
      CatalogRebuild.new(@library, apply: true).call
    end
    assert VibeModel.exists?(@mega.id)
  end

  test "mega wipe refuses flat libraries" do
    @library.update!(layout_mode: Library::LAYOUT_FLAT)
    error = assert_raises(ArgumentError) do
      CatalogRebuild.new(@library, apply: false).call
    end
    assert_match(/category_model/, error.message)
  end

  test "unknown wipe is rejected" do
    assert_raises(ArgumentError) do
      CatalogRebuild.new(@library, apply: false, wipe: "yesterday").call
    end
  end

  test "source does not unlink or rm library files" do
    sources = [
      Rails.root.join("app/services/catalog_rebuild.rb"),
      Rails.root.join("app/jobs/catalog_rebuild_job.rb"),
      Rails.root.join("lib/tasks/vibe.rake")
    ]
    sources.each do |path|
      text = File.read(path)
      refute_match(/\bFile\.(unlink|delete)\b/, text, path.to_s)
      refute_match(/FileUtils\.rm/, text, path.to_s)
      refute_match(/rm\s+-rf/, text, path.to_s)
    end
  end

  test "rebuild is not registered as a civil-hour cron" do
    text = File.read(Rails.root.join("config/initializers/sidekiq.rb"))
    refute_match(/CatalogRebuildJob/, text)
    refute_match(/\b2am\b|midnight/, text)
  end

  test "rake dry-run prints mega ids and does not delete" do
    ENV["LIBRARY_ID"] = @library.id.to_s
    ENV.delete("APPLY")
    out, = capture_io { invoke_rebuild_rake }

    assert_match(/id=#{@mega.id}/, out)
    assert_match(/folder=Anime/, out)
    assert_match(/apply=false/, out)
    assert VibeModel.exists?(@mega.id)
    assert File.exist?(@root.join("Anime/PackA/hero.stl"))
    assert_no_enqueued_jobs only: IncrementalScanJob
  end

  test "rake apply as owner wipes mega-models and leaves files" do
    ENV["LIBRARY_ID"] = @library.id.to_s
    ENV["USER_ID"] = @owner.id.to_s
    ENV["APPLY"] = "1"
    out, = capture_io { invoke_rebuild_rake }

    assert_match(/deleted=1/, out)
    assert_match(/scan_enqueued=true/, out)
    refute VibeModel.exists?(@mega.id)
    assert File.exist?(@root.join("Anime/PackA/hero.stl"))
  end

  test "rake apply without USER_ID aborts" do
    ENV["LIBRARY_ID"] = @library.id.to_s
    ENV["APPLY"] = "1"
    ENV.delete("USER_ID")
    assert_raises(SystemExit) { capture_io { invoke_rebuild_rake } }
    assert VibeModel.exists?(@mega.id)
  end

  test "rake apply as viewer aborts without deleting" do
    ENV["LIBRARY_ID"] = @library.id.to_s
    ENV["USER_ID"] = @viewer.id.to_s
    ENV["APPLY"] = "1"
    assert_raises(SystemExit) { capture_io { invoke_rebuild_rake } }
    assert VibeModel.exists?(@mega.id)
    assert File.exist?(@root.join("Anime/PackA/hero.stl"))
  end

  private

  def invoke_rebuild_rake
    task = Rake::Task["vibe:rebuild_catalog"]
    task.reenable
    task.invoke
  end

  def reset_rebuild_env!
    %w[APPLY LIBRARY_ID USER_ID WIPE].each { |key| ENV.delete(key) }
  end
end
