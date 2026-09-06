require "test_helper"
require "fileutils"
require "zip"

class ArchiveMemberGeometryFingerprintTest < ActiveSupport::TestCase
  def setup
    @root = Rails.root.join("tmp/geo-member-fp-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(@root.join("widget"))
    @library = Library.create!(name: "Geo members", root_path: @root.to_s)
    @model = @library.vibe_models.create!(folder_name: "widget", title: "Widget")
  end

  def teardown
    FileUtils.rm_rf(@root)
    %w[VIBE_GEO_MAX_BYTES VIBE_GEO_MAX_VERTS VIBE_GEO_MAX_SECONDS VIBE_GEO_QUANT].each do |key|
      ENV.delete(key)
    end
  end

  test "loose file and zip member of the same mesh share a digest" do
    write_ascii_stl(@root.join("widget/loose.stl"), CUBE_FACES, name: "export-a")
    write_obj(@root.join("widget/loose.obj"), CUBE_FACES)
    write_3mf(@root.join("widget/loose.3mf"), CUBE_FACES)
    pack_zip!(
      @root.join("widget/pack.zip"),
      "path/a.stl" => File.binread(@root.join("widget/loose.stl")),
      "path/b.obj" => File.binread(@root.join("widget/loose.obj")),
      "nested/c.3mf" => File.binread(@root.join("widget/loose.3mf"))
    )

    loose_stl = create_asset!("loose.stl", "stl")
    loose_obj = create_asset!("loose.obj", "obj")
    loose_3mf = create_asset!("loose.3mf", "3mf")
    zip = create_asset!("pack.zip", "zip")
    ArchiveIndexer.new(zip).index!

    stl_member = zip.archive_members.find_by!(internal_path: "path/a.stl")
    obj_member = zip.archive_members.find_by!(internal_path: "path/b.obj")
    threemf_member = zip.archive_members.find_by!(internal_path: "nested/c.3mf")

    digests = [
      GeometryFingerprint.compute(loose_stl),
      GeometryFingerprint.compute(loose_obj),
      GeometryFingerprint.compute(loose_3mf),
      GeometryFingerprint.compute(stl_member),
      GeometryFingerprint.compute(obj_member),
      GeometryFingerprint.compute(threemf_member)
    ]
    assert digests.all? { |digest| digest.match?(/\Amesh:v1:[0-9a-f]{64}\z/) }
    assert_equal 1, digests.uniq.size
    refute File.exist?(@root.join("widget/path/a.stl"))
  end

  test "7z member matches the same loose mesh when 7z is available" do
    skip "7z CLI not available" unless ArchiveShellLister.available?

    write_ascii_stl(@root.join("widget/loose.stl"), CUBE_FACES, name: "seven")
    write_7z!(@root.join("widget/pack.7z"), "inner/part.stl" => File.binread(@root.join("widget/loose.stl")))

    loose = create_asset!("loose.stl", "stl")
    seven = create_asset!("pack.7z", "7z")
    ArchiveIndexer.new(seven).index!
    member = seven.archive_members.find_by!(internal_path: "inner/part.stl")
    refute member.placeholder?, "expected 7z listing, got #{seven.reload.archive_support}"

    loose_digest = GeometryFingerprint.compute(loose)
    member_digest = GeometryFingerprint.compute(member)
    assert_equal loose_digest, member_digest
    assert_match(/\Amesh:v1:[0-9a-f]{64}\z/, member_digest)
    refute File.exist?(@root.join("widget/inner/part.stl"))
  end

  test "already-present member digest is not recomputed" do
    member = packed_stl_member!
    member.update!(geometry_digest: "mesh:already")

    assert_nil GeometryFingerprint.compute(member)
    assert_equal "already_present", GeometryFingerprint.new(member.reload).tap(&:compute).skip_reason
    assert_equal "mesh:already", member.reload.geometry_digest
  end

  test "jail refusal skips without crashing" do
    member = packed_stl_member!
    member.asset.update!(relative_path: "gone.zip")
    fingerprint = GeometryFingerprint.new(member)
    assert_nil fingerprint.compute
    assert_equal "jail", fingerprint.skip_reason
  end

  test "missing member skips without writing" do
    member = packed_stl_member!
    member.update!(internal_path: "missing/mesh.stl")
    fingerprint = GeometryFingerprint.new(member)
    assert_nil fingerprint.compute
    assert_equal "missing", fingerprint.skip_reason
  end

  test "non-mesh members skip cleanly" do
    zip = create_asset!("pack.zip", "zip")
    Zip::File.open(@root.join("widget/pack.zip"), Zip::File::CREATE) do |archive|
      archive.get_output_stream("notes.txt") { |io| io.write("hello") }
      archive.get_output_stream("preview.png") { |io| io.write("png") }
    end
    ArchiveIndexer.new(zip).index!

    [zip.archive_members.find_by!(internal_path: "notes.txt"),
     zip.archive_members.find_by!(internal_path: "preview.png")].each do |member|
      fingerprint = GeometryFingerprint.new(member)
      assert_nil fingerprint.compute
      assert_equal "non_mesh", fingerprint.skip_reason
    end
  end

  test "size prefilter skips a huge catalog member" do
    member = packed_stl_member!(byte_size_override: 90_000_000)
    ENV["VIBE_GEO_MAX_BYTES"] = "1024"

    fingerprint = GeometryFingerprint.new(member)
    assert_nil fingerprint.compute
    assert_equal "too_large", fingerprint.skip_reason
  end

  test "vertex budget skips instead of hashing a huge packed mesh" do
    member = packed_stl_member!
    budget = GeometryBudget.new(max_bytes: 0, max_verts: 2, max_seconds: 0)

    fingerprint = GeometryFingerprint.new(member, budget: budget)
    assert_nil fingerprint.compute
    assert_equal "too_many_verts", fingerprint.skip_reason
  end

  test "write-back apply sets archive_members.geometry_digest" do
    member = packed_stl_member!
    digest = GeometryFingerprint.compute(member)
    assert digest.present?

    GeometryWriteback.apply!(archive_member_id: member.id, geometry_digest: digest)
    assert_equal digest, member.reload.geometry_digest
  end

  private

  def create_asset!(filename, kind, geometry_digest: nil, byte_size: nil)
    path = @root.join("widget", filename)
    @model.assets.create!(
      relative_path: filename,
      filename: filename,
      kind: kind,
      byte_size: byte_size || (File.file?(path) ? File.size(path) : 0),
      geometry_digest: geometry_digest
    )
  end

  def packed_stl_member!(byte_size_override: nil)
    write_ascii_stl(@root.join("widget/part.stl"), CUBE_FACES)
    pack_zip!(@root.join("widget/pack.zip"), "path/foo.stl" => File.binread(@root.join("widget/part.stl")))
    zip = create_asset!("pack.zip", "zip")
    ArchiveIndexer.new(zip).index!
    member = zip.archive_members.find_by!(internal_path: "path/foo.stl")
    member.update!(uncompressed_size: byte_size_override) if byte_size_override
    member
  end

  def pack_zip!(path, members)
    Zip::File.open(path.to_s, Zip::File::CREATE) do |zip|
      members.each do |internal, body|
        zip.get_output_stream(internal) { |io| io.write(body) }
      end
    end
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
