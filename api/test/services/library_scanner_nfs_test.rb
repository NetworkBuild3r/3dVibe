require "test_helper"
require "fileutils"

class LibraryScannerNfsTest < ActiveJob::TestCase
  def setup
    @root = Rails.root.join("tmp/nfs-scan-#{SecureRandom.hex(4)}")
    %w[alpha bravo charlie].each do |name|
      FileUtils.mkdir_p(@root.join(name))
      File.write(@root.join(name, "#{name}.txt"), name)
    end
    @library = Library.create!(name: "NFS", root_path: @root.to_s)
  end

  def teardown
    restore_scan_env
    FileUtils.rm_rf(@root)
  end

  test "folder budget stops the run and the next scan resumes from the cursor" do
    with_scan_env("VIBE_SCAN_MAX_FOLDERS" => "1", "VIBE_SCAN_MAX_FILES" => "0", "VIBE_SCAN_MAX_SECONDS" => "0") do
      first = LibraryScanner.new(@library, budget: ScanBudget.from_env, trigger: "inline").scan!
      assert_equal ScanRun::BUDGETED, first.status
      assert first.budget_exhausted
      assert_equal "alpha", first.resume_after
      assert_equal %w[alpha], @library.vibe_models.order(:folder_name).pluck(:folder_name)

      second = LibraryScanner.new(@library, budget: ScanBudget.from_env).scan!(run: first)
      assert_equal ScanRun::BUDGETED, second.status
      assert_equal "bravo", second.resume_after
      assert_equal %w[alpha bravo], @library.vibe_models.order(:folder_name).pluck(:folder_name)

      third = LibraryScanner.new(@library, budget: ScanBudget.from_env).scan!(run: second)
      assert_equal ScanRun::COMPLETED, third.status
      refute third.budget_exhausted
      assert_nil third.resume_after
      assert_equal %w[alpha bravo charlie], @library.vibe_models.order(:folder_name).pluck(:folder_name)
    end
  end

  test "file budget resumes mid-folder via the scan cursor" do
    FileUtils.rm_rf(@root.join("alpha"))
    FileUtils.mkdir_p(@root.join("alpha"))
    File.write(@root.join("alpha/a.txt"), "a")
    File.write(@root.join("alpha/b.txt"), "b")
    File.write(@root.join("alpha/c.txt"), "c")
    FileUtils.rm_rf(@root.join("bravo"))
    FileUtils.rm_rf(@root.join("charlie"))

    with_scan_env("VIBE_SCAN_MAX_FILES" => "1", "VIBE_SCAN_MAX_FOLDERS" => "0", "VIBE_SCAN_MAX_SECONDS" => "0") do
      first = LibraryScanner.new(@library, budget: ScanBudget.from_env).scan!
      assert_equal ScanRun::BUDGETED, first.status
      cursor = @library.scan_cursors.find_by!(path_prefix: "alpha")
      assert_equal "a.txt", cursor.resume_relative_path
      assert_equal 1, @library.vibe_models.find_by!(folder_name: "alpha").assets.count

      second = LibraryScanner.new(@library, budget: ScanBudget.from_env).scan!(run: first)
      assert_equal "b.txt", cursor.reload.resume_relative_path
      assert_equal 2, @library.vibe_models.find_by!(folder_name: "alpha").assets.count

      third = LibraryScanner.new(@library, budget: ScanBudget.from_env).scan!(run: second)
      assert_equal ScanRun::COMPLETED, third.status
      assert_nil cursor.reload.resume_relative_path
      assert_equal 3, @library.vibe_models.find_by!(folder_name: "alpha").assets.count
    end
  end

  test "full walk prunes disappeared folders in batches and enqueues a Meili reindex" do
    LibraryScanner.new(@library, budget: ScanBudget.unlimited).scan!
    assert_equal 3, @library.vibe_models.count
    FileUtils.rm_rf(@root.join("bravo"))
    FileUtils.rm_rf(@root.join("charlie"))

    with_scan_env("VIBE_SCAN_PRUNE_BATCH" => "1", "VIBE_SCAN_MAX_FOLDERS" => "0", "VIBE_SCAN_MAX_FILES" => "0") do
      first = LibraryScanner.new(@library, budget: ScanBudget.from_env).scan!
      assert_equal ScanRun::BUDGETED, first.status
      assert_equal ScanRun::PHASE_PRUNE, first.phase
      assert_equal 1, first.pruned_count
      assert_equal 2, @library.vibe_models.count

      assert_enqueued_with(job: ReindexSearchJob, args: [@library.id]) do
        second = LibraryScanner.new(@library, budget: ScanBudget.from_env).scan!(run: first)
        assert_equal ScanRun::COMPLETED, second.status
        assert_equal 2, second.pruned_count
      end
      assert_equal %w[alpha], @library.vibe_models.pluck(:folder_name)
      refute @library.scan_cursors.exists?(path_prefix: "bravo")
    end
  end

  test "budgeted walk does not prune folders that have not been visited yet" do
    LibraryScanner.new(@library, budget: ScanBudget.unlimited).scan!
    FileUtils.rm_rf(@root.join("charlie"))

    with_scan_env(
      "VIBE_SCAN_MAX_FOLDERS" => "1",
      "VIBE_SCAN_MAX_FILES" => "0",
      "VIBE_SCAN_MAX_SECONDS" => "0",
      "VIBE_SCAN_TRUST_DIR_MTIME" => "0"
    ) do
      run = LibraryScanner.new(@library, budget: ScanBudget.from_env).scan!
      assert_equal ScanRun::BUDGETED, run.status
      assert @library.vibe_models.exists?(folder_name: "charlie")
    end
  end

  test "refuses to prune the catalog when the mount lists zero folders" do
    LibraryScanner.new(@library, budget: ScanBudget.unlimited).scan!
    FileUtils.rm_rf(@root.join("alpha"))
    FileUtils.rm_rf(@root.join("bravo"))
    FileUtils.rm_rf(@root.join("charlie"))

    run = LibraryScanner.new(@library, budget: ScanBudget.unlimited).scan!
    assert_equal ScanRun::COMPLETED, run.status
    assert_equal 3, @library.vibe_models.count
    assert_match(/refusing to prune/, run.last_error)
  end

  test "cheap dir identity skip avoids a deep walk until the interval elapses" do
    first = LibraryScanner.new(@library, budget: ScanBudget.unlimited).scan!
    assert first.deep_walks >= 3

    second = LibraryScanner.new(@library, budget: ScanBudget.unlimited).scan!
    assert_equal 0, second.deep_walks
    assert second.folders_skipped >= 3

    cursor = @library.scan_cursors.find_by!(path_prefix: "alpha")
    cursor.update!(last_deep_scanned_at: 7.hours.ago)
    third = LibraryScanner.new(@library, budget: ScanBudget.unlimited).scan!
    assert third.deep_walks >= 1
  end

  test "inode change on a file is treated as a content change" do
    LibraryScanner.new(@library, budget: ScanBudget.unlimited).scan!
    asset = @library.vibe_models.find_by!(folder_name: "alpha").assets.find_by!(filename: "alpha.txt")
    asset.update_column(:inode, 999_999)
    @library.scan_cursors.find_by!(path_prefix: "alpha").update!(
      last_dir_mtime: 1.day.ago,
      last_deep_scanned_at: 1.day.ago
    )

    run = LibraryScanner.new(@library, budget: ScanBudget.unlimited).scan!
    asset.reload
    assert_operator run.files_changed, :>=, 1
    assert_not_equal 999_999, asset.inode
    assert asset.inode.present?
  end

  test "incremental job re-enqueues when the run is budgeted" do
    with_scan_env("VIBE_SCAN_MAX_FOLDERS" => "1", "VIBE_SCAN_MAX_FILES" => "0", "VIBE_SCAN_MAX_SECONDS" => "0") do
      IncrementalScanJob.perform_now(@library.id)
      assert @library.scan_runs.where(status: ScanRun::BUDGETED).exists?
      assert_enqueued_jobs 1, only: IncrementalScanJob
    end
  end

  private

  def with_scan_env(values)
    previous = {}
    values.each do |key, value|
      previous[key] = ENV[key]
      ENV[key] = value
    end
    yield
  ensure
    values.each_key do |key|
      if previous[key].nil?
        ENV.delete(key)
      else
        ENV[key] = previous[key]
      end
    end
  end

  def restore_scan_env
    %w[
      VIBE_SCAN_MAX_SECONDS VIBE_SCAN_MAX_FILES VIBE_SCAN_MAX_FOLDERS
      VIBE_SCAN_PRUNE_BATCH VIBE_SCAN_DEEP_INTERVAL VIBE_SCAN_TRUST_DIR_MTIME
      VIBE_SCAN_ALLOW_EMPTY_PRUNE
    ].each { |key| ENV.delete(key) }
  end
end
