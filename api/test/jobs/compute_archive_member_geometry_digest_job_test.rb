require "test_helper"
require "fileutils"
require "zip"

class ComputeArchiveMemberGeometryDigestJobTest < ActiveJob::TestCase
  def setup
    @root = Rails.root.join("tmp/geo-member-job-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(@root.join("packed"))
    Zip::File.open(@root.join("packed/pack.zip"), Zip::File::CREATE) do |zip|
      zip.get_output_stream("path/foo.stl") { |io| io.write("solid foo\nendsolid foo\n") }
    end
    @library = Library.create!(name: "Geo member job", root_path: @root.to_s)
    LibraryScanner.new(@library, budget: ScanBudget.unlimited).scan!
    @archive = @library.vibe_models.find_by!(folder_name: "packed").assets.find_by!(filename: "pack.zip")
    @member = @archive.archive_members.find_by!(internal_path: "path/foo.stl")
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  test "path-jails the parent archive and does not write a digest or extract" do
    assert_nothing_raised { ComputeArchiveMemberGeometryDigestJob.perform_now(@member.id) }
    assert_nil @member.reload.geometry_digest
    refute File.exist?(@root.join("packed/path/foo.stl"))
    assert File.file?(@root.join("packed/pack.zip"))
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
end
