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
    @library = Library.create!(name: "Test lib", root_path: @root.to_s)
    Membership.create!(user: @owner, library: @library, role: Membership::OWNER)
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  test "indexes folders, assets, digests, and zip members without loading unrelated files" do
    LibraryScanner.new(@library).scan!

    assert_equal 2, @library.vibe_models.count
    cube = @library.vibe_models.find_by!(folder_name: "cube-gauge")
    assert_equal "Cube Gauge", cube.title
    assert_includes cube.synopsis, "gauge cube"
    assert cube.assets.exists?(filename: "cube.stl", kind: "stl")
    assert cube.assets.find_by!(filename: "cube.stl").content_digest.present?

    pack = @library.vibe_models.find_by!(folder_name: "kit-pack")
    archive = pack.assets.find_by!(filename: "minis.zip")
    assert archive.archive?
    names = archive.archive_members.pluck(:internal_path)
    assert_includes names, "hero.stl"
    assert_includes names, "extras/readme.txt"
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
