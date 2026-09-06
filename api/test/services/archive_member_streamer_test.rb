require "test_helper"
require "fileutils"
require "zip"

class ArchiveMemberStreamerTest < ActiveSupport::TestCase
  def setup
    @root = Rails.root.join("tmp/archive-stream-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(@root.join("kit"))
    Zip::File.open(@root.join("kit/minis.zip"), Zip::File::CREATE) do |zip|
      zip.get_output_stream("path/foo.stl") { |io| io.write(stl_body) }
      zip.get_output_stream("preview/hero.png") { |io| io.write(png_bytes) }
    end

    @library = Library.create!(name: "Streams", root_path: @root.to_s)
    @model = @library.vibe_models.create!(folder_name: "kit", title: "Kit")
    @zip = @model.assets.create!(relative_path: "minis.zip", filename: "minis.zip", kind: "zip")
    ArchiveIndexer.new(@zip).index!
    @member = @zip.archive_members.find_by!(internal_path: "path/foo.stl")
  end

  def teardown
    FileUtils.rm_rf(@root)
    ENV.delete("VIBE_ARCHIVE_STREAM_BYTES")
    ENV.delete("VIBE_ARCHIVE_STREAM_SECONDS")
  end

  test "streams one zip member in chunks without writing into the library" do
    chunks = []
    ArchiveMemberStreamer.for_member(@member).each { |chunk| chunks << chunk }

    assert_operator chunks.size, :>=, 1
    assert_equal stl_body, chunks.join
    refute File.exist?(@root.join("kit/path/foo.stl"))
    refute File.exist?(@root.join("kit/foo.stl"))
  end

  test "range skip yields a suffix without buffering the prefix" do
    body = +""
    ArchiveMemberStreamer.for_member(@member).each(offset: 6, length: 4) { |chunk| body << chunk }
    assert_equal "cube", body
  end

  test "refuses oversized members before copying" do
    error = assert_raises(ArgumentError) do
      ArchiveMemberStreamer.for_member(@member).each(max_bytes: 4) { flunk "should not yield" }
    end
    assert_match(/oversized/, error.message)
  end

  test "times out a slow consumer" do
    error = assert_raises(ArgumentError) do
      ArchiveMemberStreamer.for_member(@member).each(max_seconds: 0.05) do
        sleep 1
      end
    end
    assert_match(/timed out/, error.message)
  end

  test "path-jails the parent archive against a symlink escape" do
    FileUtils.rm(@root.join("kit/minis.zip"))
    File.symlink("/etc/hosts", @root.join("kit/minis.zip"))

    error = assert_raises(ArgumentError) do
      ArchiveMemberStreamer.for_member(@member)
    end
    assert_match(/escape|not in the library|invalid path/i, error.message)
  end

  test "rejects an unsafe member path" do
    error = assert_raises(ArgumentError) do
      ArchiveMemberStreamer.new(@zip, "../secret.stl")
    end
    assert_match(/unsafe archive path/, error.message)
  end

  test "parse_range understands suffix and open-ended ranges" do
    range = ArchiveMemberStreamer.parse_range("bytes=0-4", total: 20)
    assert_equal 0, range.first
    assert_equal 4, range.last
    assert_equal 5, range.length

    suffix = ArchiveMemberStreamer.parse_range("bytes=-3", total: 10)
    assert_equal 7, suffix.first
    assert_equal 9, suffix.last

    open = ArchiveMemberStreamer.parse_range("bytes=8-", total: 10)
    assert_equal 8, open.first
    assert_equal 9, open.last

    assert_equal :unsatisfiable, ArchiveMemberStreamer.parse_range("bytes=80-90", total: 20)
    assert_nil ArchiveMemberStreamer.parse_range(nil, total: 20)
  end

  test "client abort closes the stream without leaking a library extract" do
    yielded = false
    ArchiveMemberStreamer.for_member(@member).each do |_chunk|
      yielded = true
      raise IOError, "closed"
    end
    assert yielded
    refute File.exist?(@root.join("kit/path/foo.stl"))
  end

  test "7z stream-one matches the zip member when the CLI is present" do
    skip "7z CLI not available" unless ArchiveShellLister.available?

    write_7z!(@root.join("kit/pack.7z"), "inner/part.stl" => stl_body)
    seven = @model.assets.create!(relative_path: "pack.7z", filename: "pack.7z", kind: "7z")
    ArchiveIndexer.new(seven).index!
    member = seven.archive_members.find_by!(internal_path: "inner/part.stl")
    refute member.placeholder?

    body = +""
    ArchiveMemberStreamer.for_member(member).each { |chunk| body << chunk }
    assert_equal stl_body, body
    refute File.exist?(@root.join("kit/inner/part.stl"))
  end

  test "extract_tempfile still path-jails for fingerprint callers" do
    tmp = ArchiveIndexer.new(@zip).extract_member("path/foo.stl")
    assert_includes File.read(tmp.path), "solid cube"
    refute tmp.path.start_with?(@root.to_s)
  ensure
    tmp&.close!
  end

  private

  def stl_body
    "solid cube\nendsolid cube\n"
  end

  def png_bytes
    ["89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000a49444154789c63000100000500010d0a2db40000000049454e44ae426082"].pack("H*")
  end

  def write_7z!(archive_path, members)
    Dir.mktmpdir do |dir|
      rels = members.map do |internal, body|
        dest = File.join(dir, internal)
        FileUtils.mkdir_p(File.dirname(dest))
        File.binwrite(dest, body)
        internal
      end
      Dir.chdir(dir) do
        ok = system(ArchiveShellLister.binary, "a", "-y", archive_path.to_s, *rels, out: File::NULL, err: File::NULL)
        raise "7z create failed" unless ok
      end
    end
  end
end
