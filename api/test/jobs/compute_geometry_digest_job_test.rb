require "test_helper"
require "fileutils"

class ComputeGeometryDigestJobTest < ActiveJob::TestCase
  def setup
    @root = Rails.root.join("tmp/geo-job-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(@root.join("crate"))
    File.write(
      @root.join("crate/box.stl"),
      "solid box\n  facet normal 0 0 1\n    outer loop\n      vertex 0 0 0\n      vertex 1 0 0\n      vertex 0 1 0\n    endloop\n  endfacet\nendsolid box\n"
    )
    @library = Library.create!(name: "Geo job", root_path: @root.to_s)
    @model = @library.vibe_models.create!(folder_name: "crate", title: "Crate")
    @asset = @model.assets.create!(
      relative_path: "box.stl",
      filename: "box.stl",
      kind: "stl",
      byte_size: File.size(@root.join("crate/box.stl"))
    )
  end

  def teardown
    FileUtils.rm_rf(@root)
    %w[VIBE_GEO_MAX_BYTES VIBE_GEO_MAX_VERTS].each { |key| ENV.delete(key) }
  end

  test "happy path writes geometry_digest via GeometryWriteback" do
    ComputeGeometryDigestJob.perform_now(@asset.id)

    digest = @asset.reload.geometry_digest
    assert_match(/\Amesh:v1:[0-9a-f]{64}\z/, digest)

    other = @model.assets.create!(
      relative_path: "copy.stl",
      filename: "copy.stl",
      kind: "stl",
      byte_size: 1
    )
    GeometryWriteback.apply!(asset_id: other.id, geometry_digest: digest)
    assert_equal digest, other.reload.geometry_digest
  end

  test "jail refusal does not write a digest" do
    @asset.update!(relative_path: "missing.stl")

    assert_nothing_raised { ComputeGeometryDigestJob.perform_now(@asset.id) }
    assert_nil @asset.reload.geometry_digest
  end

  test "non-mesh skip does not write a digest" do
    File.write(@root.join("crate/notes.txt"), "hello")
    notes = @model.assets.create!(
      relative_path: "notes.txt",
      filename: "notes.txt",
      kind: "txt",
      byte_size: 5
    )

    assert_nothing_raised { ComputeGeometryDigestJob.perform_now(notes.id) }
    assert_nil notes.reload.geometry_digest
  end

  test "size prefilter skip does not write a digest" do
    ENV["VIBE_GEO_MAX_BYTES"] = "10"

    assert_nothing_raised { ComputeGeometryDigestJob.perform_now(@asset.id) }
    assert_nil @asset.reload.geometry_digest
  end

  test "existing digest is left alone" do
    @asset.update!(geometry_digest: "mesh:keep-me")

    ComputeGeometryDigestJob.perform_now(@asset.id)
    assert_equal "mesh:keep-me", @asset.reload.geometry_digest
  end
end
