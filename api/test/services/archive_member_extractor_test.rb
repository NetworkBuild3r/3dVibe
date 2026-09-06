require "test_helper"
require "fileutils"
require "zip"

class ArchiveMemberExtractorTest < ActiveSupport::TestCase
  def setup
    @root = Rails.root.join("tmp/extract-lib-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(@root.join("packed"))
    Zip::File.open(@root.join("packed/pack.zip"), Zip::File::CREATE) do |zip|
      zip.get_output_stream("path/foo.stl") { |io| io.write(stl_body) }
      zip.get_output_stream("noise/huge.bin") { |io| io.write("X" * 64 * 1024) }
    end
    FileUtils.mkdir_p(@root.join("crate"))
    File.write(@root.join("crate/box.stl"), "solid box\nendsolid box\n")

    @owner = create_owner!
    @library = Library.create!(name: "Extract pile", root_path: @root.to_s)
    Membership.create!(user: @owner, library: @library, role: Membership::OWNER)
    LibraryScanner.new(@library, budget: ScanBudget.unlimited).scan!
    @member = packed_member("path/foo.stl")
    @noise = packed_member("noise/huge.bin")
    @crate = @library.vibe_models.find_by!(folder_name: "crate")
    @zip_bytes = File.binread(@root.join("packed/pack.zip"))
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  test "extract streams one member into a first-level model folder and leaves the zip packed" do
    result = extractor.extract!(archive_member_ids: [@member.id], title: "Pulled meshes")
    folder = result.model.folder_name

    assert_equal "Pulled meshes", result.model.title
    assert_equal 1, result.extracted.size
    assert_equal true, result.extracted.first[:mergeable]
    assert_equal @member.id, result.extracted.first[:archive_member_id]
    assert result.assets.first
    assert File.file?(@root.join("#{folder}/foo.stl"))
    assert_equal stl_body, File.binread(@root.join("#{folder}/foo.stl"))
    refute File.exist?(@root.join("packed/path/foo.stl"))
    refute File.exist?(@root.join("#{folder}/huge.bin"))
    refute File.exist?(@root.join("#{folder}/noise/huge.bin"))
    assert File.file?(@root.join("packed/pack.zip"))
    assert_equal @zip_bytes, File.binread(@root.join("packed/pack.zip"))
  end

  test "extract does not load the parent archive into RAM" do
    zip_path = @root.join("packed/pack.zip").realpath.to_s
    guard_whole_archive_binread!(zip_path) do
      result = extractor.extract!(archive_member_ids: [@member.id], target_id: @crate.id)
      assert File.file?(@root.join("crate/foo.stl"))
      refute File.exist?(@root.join("crate/huge.bin"))
      assert_equal @member.id, result.extracted.first[:archive_member_id]
      assert_equal true, result.extracted.first[:mergeable]
    end
    assert_equal @zip_bytes, File.binread(zip_path)
    refute File.exist?(@root.join("packed/path/foo.stl"))
    assert File.file?(@root.join("packed/pack.zip"))
  end

  test "extract then ModelComposer merge reparents the new on-disk asset" do
    result = extractor.extract!(archive_member_ids: [@member.id], title: "From pack")
    asset = result.assets.first
    assert asset
    assert File.file?(@root.join("#{result.model.folder_name}/foo.stl"))

    merge = ModelComposer.new(@library, performed_by: @owner).merge!(
      asset_ids: [asset.id],
      target_id: @crate.id
    )
    assert File.file?(@root.join("crate/#{result.model.folder_name}/foo.stl"))
    refute File.exist?(@root.join("#{result.model.folder_name}/foo.stl"))
    assert_includes merge.parts.first["files"], "#{result.model.folder_name}/foo.stl"
    assert @crate.reload.assets.exists?(filename: "foo.stl")
  end

  test "extract_and_merge copies the member then merges a loose asset into the same folder" do
    loose = @crate.assets.find_by!(filename: "box.stl")
    result = extractor.extract_and_merge!(
      archive_member_ids: [@member.id],
      asset_ids: [loose.id],
      title: "Horn kit"
    )

    target = result.model
    assert_equal "Horn kit", target.title
    assert File.file?(@root.join("#{target.folder_name}/foo.stl"))
    assert File.file?(@root.join("#{target.folder_name}/crate/box.stl"))
    assert_equal true, result.extracted.first[:mergeable]
    assert result.merge
    assert File.file?(@root.join("packed/pack.zip"))
    refute File.exist?(@root.join("packed/path/foo.stl"))
  end

  test "extract rejects a jail-escaping folder name" do
    assert_raises(ArgumentError) do
      extractor.extract!(archive_member_ids: [@member.id], folder_name: "../etc")
    end
    refute File.exist?(@root.join("../etc"))
    refute File.exist?(Pathname.new(@root).join("..", "etc", "foo.stl"))
    assert File.file?(@root.join("packed/pack.zip"))
    assert_equal @zip_bytes, File.binread(@root.join("packed/pack.zip"))
  end

  test "extract rejects a tampered member basename that would escape the jail" do
    @member.update_columns(internal_path: "foo.stl", basename: "../outside.stl")
    error = assert_raises(ArgumentError) do
      extractor.extract!(archive_member_ids: [@member.id], title: "Nope")
    end
    assert_match(/invalid path|path escapes/i, error.message)
    refute File.exist?(@root.join("outside.stl"))
    refute File.exist?(Pathname.new(@root).join("..", "outside.stl"))
  end

  test "extract does not write sibling zip members" do
    extractor.extract!(archive_member_ids: [@member.id], target_id: @crate.id)
    refute File.exist?(@root.join("crate/huge.bin"))
    refute File.exist?(@root.join("crate/noise/huge.bin"))
    assert File.file?(@root.join("crate/foo.stl"))
    assert_nil @noise.asset.vibe_model.assets.find_by(filename: "huge.bin")
  end

  private

  def extractor
    ArchiveMemberExtractor.new(@library, performed_by: @owner)
  end

  def packed_member(internal_path)
    archive = @library.vibe_models.find_by!(folder_name: "packed").assets.find_by!(filename: "pack.zip")
    archive.archive_members.find_by!(internal_path: internal_path)
  end

  def stl_body
    "solid foo\nendsolid foo\n"
  end

  def guard_whole_archive_binread!(zip_path)
    file_class = File.singleton_class
    file_class.alias_method :binread_without_extract_guard, :binread
    file_class.define_method(:binread) do |name, *args|
      path = File.expand_path(name.to_s)
      limit = args.first
      whole = limit.nil? || (limit.respond_to?(:to_i) && File.file?(path) && limit.to_i >= File.size(path))
      raise "whole-archive RAM load via File.binread" if path == zip_path && whole

      binread_without_extract_guard(name, *args)
    end
    yield
  ensure
    file_class.alias_method :binread, :binread_without_extract_guard
    file_class.remove_method :binread_without_extract_guard
  end
end
