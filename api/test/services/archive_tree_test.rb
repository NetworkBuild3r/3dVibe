require "test_helper"
require "fileutils"
require "zip"

class ArchiveTreeTest < ActiveSupport::TestCase
  def setup
    @root = Rails.root.join("tmp/archive-tree-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(@root.join("kit"))
    Zip::File.open(@root.join("kit/minis.zip"), Zip::File::CREATE) do |zip|
      zip.get_output_stream("hero.stl") { |io| io.write("solid x\nendsolid x\n") }
      zip.get_output_stream("extras/readme.txt") { |io| io.write("note") }
      zip.get_output_stream("extras/nested/note.txt") { |io| io.write("deep") }
    end
    @library = Library.create!(name: "Tree", root_path: @root.to_s)
    LibraryScanner.new(@library).scan!
    @model = @library.vibe_models.find_by!(folder_name: "kit")
    @asset = @model.assets.find_by!(filename: "minis.zip")
    @scope = @asset.archive_members
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  test "returns immediate children and lazy nested folders" do
    tree = ArchiveTree.new(@scope)
    roots, total, counts = tree.children(prefix: "", limit: 50, offset: 0)
    names = roots.map(&:basename)
    assert_includes names, "hero.stl"
    assert_includes names, "extras"
    refute_includes roots.map(&:internal_path), "extras/readme.txt"
    assert_equal counts["extras/"], 2
    assert total >= 2

    nested, = tree.children(prefix: "extras/", limit: 50, offset: 0)
    nested_names = nested.map(&:basename)
    assert_includes nested_names, "readme.txt"
    assert_includes nested_names, "nested"
  end

  test "search finds a member path without dumping the whole tree" do
    tree = ArchiveTree.new(@scope)
    hits, total = tree.search(query: "hero", limit: 20, offset: 0)
    assert_equal 1, total
    assert_equal ["hero.stl"], hits.map(&:basename)
  end

  test "paginates children with offset" do
    tree = ArchiveTree.new(@scope)
    page, total = tree.flat(limit: 2, offset: 0)
    assert_equal 2, page.size
    assert total > 2
    rest, = tree.flat(limit: 50, offset: 2)
    refute_equal page.map(&:id), rest.first(2).map(&:id)
  end
end
