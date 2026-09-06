require "test_helper"
require "fileutils"
require "zip"

class ArchiveIndexerTest < ActiveSupport::TestCase
  def setup
    @root = Rails.root.join("tmp/archive-idx-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(@root.join("kit"))
    Zip::File.open(@root.join("kit/minis.zip"), Zip::File::CREATE) do |zip|
      zip.get_output_stream("hero.stl") { |io| io.write(stl_body) }
      zip.get_output_stream("preview/hero.png") { |io| io.write(png_bytes) }
      zip.get_output_stream("extras/nested/note.txt") { |io| io.write("deep") }
    end
    File.binwrite(@root.join("kit/notes.7z"), "not a real 7z\n")
    Zip::File.open(@root.join("kit/kit.3mf"), Zip::File::CREATE) do |zip|
      zip.get_output_stream("3D/3dmodel.model") { |io| io.write("<model/>") }
    end

    @library = Library.create!(name: "Archives", root_path: @root.to_s)
    @model = @library.vibe_models.create!(folder_name: "kit", title: "Kit")
    @zip = @model.assets.create!(relative_path: "minis.zip", filename: "minis.zip", kind: "zip")
    @seven = @model.assets.create!(relative_path: "notes.7z", filename: "notes.7z", kind: "7z")
    @threemf = @model.assets.create!(relative_path: "kit.3mf", filename: "kit.3mf", kind: "3mf")
  end

  def teardown
    FileUtils.rm_rf(@root)
    ENV.delete("VIBE_ARCHIVE_MEMBER_LIMIT")
    ENV.delete("VIBE_ARCHIVE_STREAM_BYTES")
  end

  test "indexes zip members and synthesizes parent folders" do
    ArchiveIndexer.new(@zip).index!

    paths = @zip.archive_members.order(:internal_path).pluck(:internal_path)
    assert_includes paths, "hero.stl"
    assert_includes paths, "preview/"
    assert_includes paths, "preview/hero.png"
    assert_includes paths, "extras/"
    assert_includes paths, "extras/nested/"
    assert_includes paths, "extras/nested/note.txt"
    assert_equal "full", @zip.reload.archive_support
    refute @zip.archive_truncated

    png = @zip.archive_members.find_by!(internal_path: "preview/hero.png")
    assert_equal "preview/", png.parent_path
    assert_equal "hero.png", png.basename
    assert_equal "image/png", png.content_type
    assert png.image?
    assert png.has_preview?
  end

  test "indexes 3mf as a zip-family archive" do
    ArchiveIndexer.new(@threemf).index!
    paths = @threemf.archive_members.pluck(:internal_path)
    assert_includes paths, "3D/"
    assert_includes paths, "3D/3dmodel.model"
    assert_equal "full", @threemf.reload.archive_support
  end

  test "7z without a usable listing becomes a placeholder" do
    ArchiveIndexer.new(@seven).index!
    members = @seven.archive_members
    assert_equal 1, members.count
    assert members.first.placeholder?
    assert_equal Asset::ARCHIVE_SUPPORT_PLACEHOLDER, @seven.reload.archive_support
  end

  test "caps huge archives instead of loading every member" do
    ENV["VIBE_ARCHIVE_MEMBER_LIMIT"] = "2"
    Zip::File.open(@root.join("kit/huge.zip"), Zip::File::CREATE) do |zip|
      8.times { |i| zip.get_output_stream("part-#{i}.stl") { |io| io.write(stl_body) } }
    end
    huge = @model.assets.create!(relative_path: "huge.zip", filename: "huge.zip", kind: "zip")

    ArchiveIndexer.new(huge).index!

    files = huge.archive_members.where(directory: false)
    assert_operator files.count, :<=, 2
    assert huge.reload.archive_truncated
  end

  test "streams one zip member without reading the archive as a string" do
    ArchiveIndexer.new(@zip).index!
    tmp = ArchiveIndexer.new(@zip).extract_member("hero.stl")
    assert_includes File.read(tmp.path), "solid cube"
  ensure
    tmp&.close!
  end

  test "refuses oversized member streams" do
    ENV["VIBE_ARCHIVE_STREAM_BYTES"] = "8"
    ArchiveIndexer.new(@zip).index!
    error = assert_raises(ArgumentError) do
      ArchiveIndexer.new(@zip).extract_member("hero.stl")
    end
    assert_match(/oversized/, error.message)
  end

  test "parses 7z slt listing output" do
    output = <<~SLT
      Path = /tmp/sample.7z
      Type = 7z

      Path = extras
      Folder = +
      Size = 0
      Packed Size = 0
      Modified = 2026-01-01 12:00:00

      Path = extras/hero.stl
      Folder = -
      Size = 42
      Packed Size = 20
      Modified = 2026-01-01 12:00:00
    SLT

    entries = ArchiveShellLister.parse_slt(output)
    assert_equal 2, entries.size
    assert entries.first.directory
    file = entries.last
    refute file.directory
    assert_equal "extras/hero.stl", file.path
    assert_equal 42, file.size
  end

  private

  def stl_body
    "solid cube\nendsolid cube\n"
  end

  def png_bytes
    ["89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000a49444154789c63000100000500010d0a2db40000000049454e44ae426082"].pack("H*")
  end
end
