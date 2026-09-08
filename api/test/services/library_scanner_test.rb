require "test_helper"
require "fileutils"
require "zip"

class LibraryScannerTest < ActiveSupport::TestCase
  def setup
    @root = Rails.root.join("tmp/test-library-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(@root.join("cube-gauge"))
    File.write(@root.join("cube-gauge/notes.txt"), "A 20mm gauge cube.")
    File.write(@root.join("cube-gauge/cube.stl"), stl_body)
    FileUtils.mkdir_p(@root.join("kit-pack"))
    Zip::File.open(@root.join("kit-pack/minis.zip"), Zip::File::CREATE) do |zip|
      zip.get_output_stream("hero.stl") { |io| io.write(stl_body) }
      zip.get_output_stream("extras/readme.txt") { |io| io.write("packed minis") }
    end

    @owner = create_owner!
    @library = Library.create!(name: "Test lib", root_path: @root.to_s, layout_mode: Library::LAYOUT_FLAT)
    Membership.create!(user: @owner, library: @library, role: Membership::OWNER)
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  test "indexes folders, assets, digests, and zip members without loading unrelated files" do
    LibraryScanner.new(@library).scan!

    assert_equal 2, @library.vibe_models.count
    cube = @library.vibe_models.find_by!(folder_name: "cube-gauge")
    assert_nil cube.uploaded_by_id
    assert_equal "Cube Gauge", cube.title
    assert_includes cube.synopsis, "gauge cube"
    assert cube.assets.exists?(filename: "cube.stl", kind: "stl")
    assert cube.assets.find_by!(filename: "cube.stl").content_digest.present?

    pack = @library.vibe_models.find_by!(folder_name: "kit-pack")
    archive = pack.assets.find_by!(filename: "minis.zip")
    assert archive.archive?
    names = archive.archive_members.pluck(:internal_path)
    assert_includes names, "hero.stl"
    assert_includes names, "extras/"
    assert_includes names, "extras/readme.txt"
    assert_equal "full", archive.reload.archive_support
    assert @library.scan_cursors.exists?(path_prefix: "cube-gauge")
  end

  test "skips unchanged folders using scan cursors" do
    LibraryScanner.new(@library).scan!
    cursor = @library.scan_cursors.find_by!(path_prefix: "cube-gauge")
    first_scan = cursor.last_scanned_at

    travel 2.seconds do
      LibraryScanner.new(@library).scan!
    end

    assert_equal first_scan.to_i, cursor.reload.last_scanned_at.to_i
  end

  test "does not index a first-level folder that is a symlink out of the library" do
    outside = Rails.root.join("tmp/scan-symlink-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(outside)
    File.write(outside.join("secret.stl"), "solid outside\nendsolid outside\n")
    File.symlink(outside, @root.join("escape-pack"))

    LibraryScanner.new(@library).scan!

    refute @library.vibe_models.exists?(folder_name: "escape-pack")
    assert @library.vibe_models.exists?(folder_name: "cube-gauge")
  ensure
    FileUtils.rm_rf(outside) if defined?(outside) && outside
  end

  test "targeted scan indexes one folder and skips hidden incoming dirs" do
    FileUtils.mkdir_p(@root.join(".vibe-incoming"))
    File.write(@root.join(".vibe-incoming/partial"), "tmp")
    FileUtils.mkdir_p(@root.join("new-clip"))
    File.write(@root.join("new-clip/clip.stl"), stl_body)

    LibraryScanner.new(@library, uploaded_by: @owner).scan!(path_prefix: "new-clip")

    clip = @library.vibe_models.find_by!(folder_name: "new-clip")
    assert_equal @owner.id, clip.uploaded_by_id
    refute @library.vibe_models.exists?(folder_name: ".vibe-incoming")
    refute @library.vibe_models.exists?(folder_name: "cube-gauge")
  end

  test "reindexes when a file mtime or size changes" do
    LibraryScanner.new(@library).scan!
    sleep 1
    File.write(@root.join("cube-gauge/cube.stl"), "#{stl_body}\n")

    LibraryScanner.new(@library).scan!
    cube = @library.vibe_models.find_by!(folder_name: "cube-gauge")
    assert cube.assets.find_by!(filename: "cube.stl").byte_size.positive?
  end

  test "category_model admits Category/Pack models and never a category named Anime" do
    pack_root = Rails.root.join("tmp/test-packs-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(pack_root.join("Anime/PackA/stl"))
    File.write(pack_root.join("Anime/PackA/notes.txt"), "eren")
    File.write(pack_root.join("Anime/PackA/stl/body.stl"), stl_body)
    FileUtils.mkdir_p(pack_root.join("Anime/PackB"))
    File.write(pack_root.join("Anime/PackB/hero.stl"), stl_body)
    FileUtils.mkdir_p(pack_root.join("EmptyCat"))
    File.write(pack_root.join("Anime/loose-at-category.txt"), "skip files at category root")

    library = Library.create!(name: "Packs", root_path: pack_root.to_s, layout_mode: Library::LAYOUT_CATEGORY_MODEL)
    LibraryScanner.new(library).scan!

    names = library.vibe_models.order(:folder_name).pluck(:folder_name)
    assert_equal %w[Anime/PackA Anime/PackB], names
    refute library.vibe_models.exists?(folder_name: "Anime")
    refute library.vibe_models.exists?(title: "Anime")
    pack_a = library.vibe_models.find_by!(folder_name: "Anime/PackA")
    assert_equal "Anime", pack_a.category
    assert_equal "Packa", pack_a.title
    assert pack_a.assets.exists?(relative_path: "stl/body.stl")
    assert_equal 0, library.vibe_models.where(folder_name: "EmptyCat").count
  ensure
    FileUtils.rm_rf(pack_root) if defined?(pack_root) && pack_root
  end

  test "category_model scan applies datapackage creator and keywords" do
    pack_root = Rails.root.join("tmp/test-dp-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(pack_root.join("Anime/Death Gun"))
    File.write(pack_root.join("Anime/Death Gun/preview.jpg"), "jpg")
    File.write(
      pack_root.join("Anime/Death Gun/datapackage.json"),
      JSON.generate(
        "title" => "Death Gun",
        "keywords" => ["anime", "helmet", "!new", "do3d"],
        "contributors" => [{ "title" => "DO3D", "roles" => ["creator"] }]
      )
    )

    library = Library.create!(name: "DP packs", root_path: pack_root.to_s, layout_mode: Library::LAYOUT_CATEGORY_MODEL)
    LibraryScanner.new(library).scan!

    model = library.vibe_models.find_by!(folder_name: "Anime/Death Gun")
    assert_equal "do3d", model.creator&.slug
    assert_equal "DO3D", model.creator&.name
    assert_equal "Death Gun", model.title
    names = model.tags.map(&:name)
    assert_includes names, "anime"
    assert_includes names, "helmet"
    assert_includes names, "do3d"
    refute_includes names, "!new"
  ensure
    FileUtils.rm_rf(pack_root) if defined?(pack_root) && pack_root
  end

  test "category_model common subfolder under a pack is not a third model" do
    pack_root = Rails.root.join("tmp/test-common-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(pack_root.join("Movie TV/Reinhardt/stl"))
    FileUtils.mkdir_p(pack_root.join("Movie TV/Reinhardt/presupported"))
    File.write(pack_root.join("Movie TV/Reinhardt/preview.jpg"), "jpg")
    File.write(pack_root.join("Movie TV/Reinhardt/stl/body.stl"), stl_body)
    File.write(pack_root.join("Movie TV/Reinhardt/presupported/body_sup.stl"), stl_body)
    FileUtils.mkdir_p(pack_root.join("Movie TV/chitubox"))
    File.write(pack_root.join("Movie TV/chitubox/ignored.stl"), stl_body)

    library = Library.create!(name: "Common", root_path: pack_root.to_s, layout_mode: Library::LAYOUT_CATEGORY_MODEL)
    LibraryScanner.new(library).scan!

    names = library.vibe_models.order(:folder_name).pluck(:folder_name)
    assert_equal ["Movie TV/Reinhardt"], names
    refute library.vibe_models.exists?(folder_name: "Movie TV/stl")
    refute library.vibe_models.exists?(folder_name: "Movie TV/chitubox")
    model = library.vibe_models.find_by!(folder_name: "Movie TV/Reinhardt")
    assert model.assets.exists?(relative_path: "stl/body.stl")
    assert model.assets.exists?(relative_path: "presupported/body_sup.stl")
  ensure
    FileUtils.rm_rf(pack_root) if defined?(pack_root) && pack_root
  end

  test "admits PackA and enqueues SearchIndex before PackB indexing finishes" do
    pack_root = Rails.root.join("tmp/test-enq-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(pack_root.join("Anime/PackA"))
    File.write(pack_root.join("Anime/PackA/a.stl"), stl_body)
    FileUtils.mkdir_p(pack_root.join("Anime/PackB"))
    File.write(pack_root.join("Anime/PackB/b.stl"), stl_body)

    library = Library.create!(name: "Progressive", root_path: pack_root.to_s, layout_mode: Library::LAYOUT_CATEGORY_MODEL)
    events = []
    original_enqueue = SearchIndex.method(:enqueue)
    SearchIndex.define_singleton_method(:enqueue) do |model|
      events << [:enqueue, model.folder_name]
    end

    scanner = Class.new(LibraryScanner) do
      define_method(:index_folder) do |dir, folder_name, cursor, dir_stat|
        events << [:index_start, folder_name]
        super(dir, folder_name, cursor, dir_stat)
      end
    end
    scanner.new(library).scan!

    pack_a_enqueue = events.index([:enqueue, "Anime/PackA"])
    pack_b_start = events.index([:index_start, "Anime/PackB"])
    assert pack_a_enqueue, "expected SearchIndex.enqueue for Anime/PackA, got #{events.inspect}"
    assert pack_b_start, "expected PackB indexing to start, got #{events.inspect}"
    assert pack_a_enqueue < pack_b_start, "PackA enqueue=#{pack_a_enqueue} must precede PackB index=#{pack_b_start}: #{events.inspect}"
  ensure
    SearchIndex.define_singleton_method(:enqueue, original_enqueue) if defined?(original_enqueue) && original_enqueue
    FileUtils.rm_rf(pack_root) if defined?(pack_root) && pack_root
  end

  test "category_model budget interrupt resumes at the next pack prefix" do
    pack_root = Rails.root.join("tmp/test-budget-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(pack_root.join("Anime/PackA"))
    File.write(pack_root.join("Anime/PackA/a.stl"), stl_body)
    FileUtils.mkdir_p(pack_root.join("Anime/PackB"))
    File.write(pack_root.join("Anime/PackB/b.stl"), stl_body)

    library = Library.create!(name: "Budget packs", root_path: pack_root.to_s, layout_mode: Library::LAYOUT_CATEGORY_MODEL)
    previous = {
      "VIBE_SCAN_MAX_FOLDERS" => ENV["VIBE_SCAN_MAX_FOLDERS"],
      "VIBE_SCAN_MAX_FILES" => ENV["VIBE_SCAN_MAX_FILES"],
      "VIBE_SCAN_MAX_SECONDS" => ENV["VIBE_SCAN_MAX_SECONDS"]
    }
    ENV["VIBE_SCAN_MAX_FOLDERS"] = "1"
    ENV["VIBE_SCAN_MAX_FILES"] = "0"
    ENV["VIBE_SCAN_MAX_SECONDS"] = "0"

    first = LibraryScanner.new(library, budget: ScanBudget.from_env).scan!
    assert_equal ScanRun::BUDGETED, first.status
    assert_equal "Anime/PackA", first.resume_after
    assert_equal %w[Anime/PackA], library.vibe_models.order(:folder_name).pluck(:folder_name)
    refute library.vibe_models.exists?(folder_name: "Anime")

    second = LibraryScanner.new(library, budget: ScanBudget.from_env).scan!(run: first)
    assert_includes [ScanRun::BUDGETED, ScanRun::COMPLETED], second.status
    names = library.vibe_models.order(:folder_name).pluck(:folder_name)
    assert_equal %w[Anime/PackA Anime/PackB], names
    refute library.vibe_models.exists?(folder_name: "Anime")
  ensure
    previous&.each do |key, value|
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end
    FileUtils.rm_rf(pack_root) if defined?(pack_root) && pack_root
  end

  test "category_model refuses a pack symlink that escapes the library root" do
    pack_root = Rails.root.join("tmp/test-pack-symlink-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(pack_root.join("Anime/PackA"))
    File.write(pack_root.join("Anime/PackA/a.stl"), stl_body)
    outside = Rails.root.join("tmp/pack-escape-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(outside)
    File.write(outside.join("secret.stl"), stl_body)
    File.symlink(outside, pack_root.join("Anime/escape-pack"))

    library = Library.create!(name: "Jail packs", root_path: pack_root.to_s, layout_mode: Library::LAYOUT_CATEGORY_MODEL)
    LibraryScanner.new(library).scan!

    refute library.vibe_models.exists?(folder_name: "Anime/escape-pack")
    assert library.vibe_models.exists?(folder_name: "Anime/PackA")
    refute library.vibe_models.exists?(folder_name: "Anime")
  ensure
    FileUtils.rm_rf(outside) if defined?(outside) && outside
    FileUtils.rm_rf(pack_root) if defined?(pack_root) && pack_root
  end

  test "does not index assets through a nested directory symlink out of the library" do
    pack_root = Rails.root.join("tmp/test-nested-symlink-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(pack_root.join("Anime/PackA"))
    File.write(pack_root.join("Anime/PackA/keep.stl"), stl_body)
    outside = Rails.root.join("tmp/nested-escape-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(outside)
    File.write(outside.join("secret.stl"), stl_body)
    File.symlink(outside, pack_root.join("Anime/PackA/escape-dir"))

    library = Library.create!(name: "Nested jail", root_path: pack_root.to_s, layout_mode: Library::LAYOUT_CATEGORY_MODEL)
    LibraryScanner.new(library).scan!

    model = library.vibe_models.find_by!(folder_name: "Anime/PackA")
    assert model.assets.exists?(relative_path: "keep.stl")
    refute model.assets.exists?(relative_path: "escape-dir/secret.stl")
    refute library.vibe_models.exists?(folder_name: "Anime/escape-dir")
  ensure
    FileUtils.rm_rf(outside) if defined?(outside) && outside
    FileUtils.rm_rf(pack_root) if defined?(pack_root) && pack_root
  end

  private

  def stl_body
    <<~STL
      solid cube
        facet normal 0 0 1
          outer loop
            vertex 0 0 1
            vertex 1 0 1
            vertex 0 1 1
          endloop
        endfacet
      endsolid cube
    STL
  end
end
