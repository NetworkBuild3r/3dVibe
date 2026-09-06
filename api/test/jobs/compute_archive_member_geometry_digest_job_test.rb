require "test_helper"
require "fileutils"
require "zip"

class ComputeArchiveMemberGeometryDigestJobTest < ActiveJob::TestCase
  def setup
    @root = Rails.root.join("tmp/geo-member-job-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(@root.join("packed"))
    FileUtils.mkdir_p(@root.join("loose"))
    write_ascii_stl(@root.join("loose/box.stl"), CUBE_FACES, name: "box")
    Zip::File.open(@root.join("packed/pack.zip"), Zip::File::CREATE) do |zip|
      zip.get_output_stream("path/foo.stl") { |io| io.write(File.binread(@root.join("loose/box.stl"))) }
      zip.get_output_stream("preview/hero.png") { |io| io.write("png") }
    end
    @library = Library.create!(name: "Geo member job", root_path: @root.to_s)
    LibraryScanner.new(@library, budget: ScanBudget.unlimited).scan!
    @archive = @library.vibe_models.find_by!(folder_name: "packed").assets.find_by!(filename: "pack.zip")
    @member = @archive.archive_members.find_by!(internal_path: "path/foo.stl")
    @image = @archive.archive_members.find_by!(internal_path: "preview/hero.png")
    @loose = @library.vibe_models.find_by!(folder_name: "loose").assets.find_by!(filename: "box.stl")
  end

  def teardown
    FileUtils.rm_rf(@root)
    %w[VIBE_GEO_MAX_BYTES VIBE_GEO_MAX_VERTS VIBE_GEO_MAX_SECONDS VIBE_ARCHIVE_STREAM_BYTES].each do |key|
      ENV.delete(key)
    end
  end

  test "happy path writes mesh:v1 digest via GeometryWriteback without extracting the zip" do
    ComputeArchiveMemberGeometryDigestJob.perform_now(@member.id)

    digest = @member.reload.geometry_digest
    assert_match(/\Amesh:v1:[0-9a-f]{64}\z/, digest)
    refute File.exist?(@root.join("packed/path/foo.stl"))
    assert File.file?(@root.join("packed/pack.zip"))

    GeometryWriteback.apply!(asset_id: @loose.id, geometry_digest: digest)
    assert_equal digest, @loose.reload.geometry_digest
  end

  test "same mesh loose vs inside pack share a digest" do
    loose_digest = GeometryFingerprint.compute(@loose)
    ComputeArchiveMemberGeometryDigestJob.perform_now(@member.id)

    assert_equal loose_digest, @member.reload.geometry_digest
  end

  test "existing digest is left alone" do
    @member.update!(geometry_digest: "mesh:v1:keep")
    ComputeArchiveMemberGeometryDigestJob.perform_now(@member.id)
    assert_equal "mesh:v1:keep", @member.reload.geometry_digest
  end

  test "jail refusal does not write a digest" do
    @archive.update!(relative_path: "missing.zip")
    assert_nothing_raised { ComputeArchiveMemberGeometryDigestJob.perform_now(@member.id) }
    assert_nil @member.reload.geometry_digest
  end

  test "member path jail escape does not write a digest" do
    @member.update_columns(internal_path: "../escape.stl", parent_path: "", basename: "escape.stl")
    assert_nothing_raised { ComputeArchiveMemberGeometryDigestJob.perform_now(@member.id) }
    assert_nil @member.reload.geometry_digest
    refute File.exist?(@root.join("escape.stl"))
  end

  test "missing member skips without crashing or writing an empty digest" do
    @member.update!(internal_path: "no/such.stl")
    assert_nothing_raised { ComputeArchiveMemberGeometryDigestJob.perform_now(@member.id) }
    assert_nil @member.reload.geometry_digest
    assert_equal "", @member.geometry_digest.to_s
  end

  test "non-mesh skip does not write a digest" do
    assert_nothing_raised { ComputeArchiveMemberGeometryDigestJob.perform_now(@image.id) }
    assert_nil @image.reload.geometry_digest
  end

  test "size budget skip does not write a digest" do
    ENV["VIBE_GEO_MAX_BYTES"] = "10"
    assert_nothing_raised { ComputeArchiveMemberGeometryDigestJob.perform_now(@member.id) }
    assert_nil @member.reload.geometry_digest
  end

  test "empty mesh skips without writing a digest" do
    FileUtils.mkdir_p(@root.join("empty-pack"))
    Zip::File.open(@root.join("empty-pack/empty.zip"), Zip::File::CREATE) do |zip|
      zip.get_output_stream("blank.stl") { |io| io.write("solid foo\nendsolid foo\n") }
    end
    LibraryScanner.new(@library, budget: ScanBudget.unlimited).scan!
    empty = @library.vibe_models.find_by!(folder_name: "empty-pack").assets.find_by!(filename: "empty.zip")
    member = empty.archive_members.find_by!(internal_path: "blank.stl")

    assert_nothing_raised { ComputeArchiveMemberGeometryDigestJob.perform_now(member.id) }
    assert_nil member.reload.geometry_digest
  end
end
