require "test_helper"
require "fileutils"

class GeometryFingerprintTest < ActiveSupport::TestCase
  def setup
    @root = Rails.root.join("tmp/geom-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(@root.join("shapes"))
    @library = Library.create!(name: "Geom", root_path: @root.to_s)
    @model = @library.vibe_models.create!(folder_name: "shapes", title: "Shapes")
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  test "ascii stl, binary stl, obj, and 3mf of the same cube share a digest" do
    write_ascii_stl(@root.join("shapes/cube.stl"))
    write_binary_stl(@root.join("shapes/cube-bin.stl"))
    write_obj(@root.join("shapes/cube.obj"))
    write_3mf(@root.join("shapes/cube.3mf"))

    digests = %w[cube.stl cube-bin.stl cube.obj cube.3mf].map do |name|
      GeometryFingerprint.compute(add_asset!(name))
    end

    assert digests.all?(&:present?)
    assert_equal 1, digests.uniq.size
    assert digests.first.start_with?("qv1:")
  end

  test "translation and uniform scale still match after normalize" do
    write_ascii_stl(@root.join("shapes/cube.stl"))
    write_ascii_stl(@root.join("shapes/moved.stl"), transformed_faces(CUBE_FACES, scale: 2.5, offset: [10, -3, 4]))

    a = GeometryFingerprint.compute(add_asset!("cube.stl"))
    b = GeometryFingerprint.compute(add_asset!("moved.stl"))
    assert_equal a, b
  end

  test "a different mesh does not share the digest" do
    write_ascii_stl(@root.join("shapes/cube.stl"))
    write_ascii_stl(@root.join("shapes/tetra.stl"), TETRA_FACES, name: "tetra")

    a = GeometryFingerprint.compute(add_asset!("cube.stl"))
    b = GeometryFingerprint.compute(add_asset!("tetra.stl"))
    refute_equal a, b
  end

  test "skips huge files without reading them as a string" do
    File.write(@root.join("shapes/huge.stl"), "x" * 4096)
    asset = add_asset!("huge.stl")
    previous = ENV["VIBE_GEOM_MAX_BYTES"]
    ENV["VIBE_GEOM_MAX_BYTES"] = "1024"
    assert_nil GeometryFingerprint.compute(asset)
  ensure
    ENV["VIBE_GEOM_MAX_BYTES"] = previous
  end

  test "times out cleanly when the clock budget is already spent" do
    write_ascii_stl(@root.join("shapes/cube.stl"))
    asset = add_asset!("cube.stl")
    ticks = 0
    clock = lambda do
      ticks += 1
      ticks == 1 ? 0.0 : GeometrySettings.max_seconds + 1
    end
    assert_nil GeometryFingerprint.compute(asset, clock: clock)
  end

  test "refuses a path that escapes the library jail" do
    File.write(@root.join("shapes/cube.stl"), "solid x\nendsolid x\n")
    asset = add_asset!("cube.stl")
    asset.update_column(:relative_path, "../outside.stl")
    assert_nil GeometryFingerprint.compute(asset)
  end

  test "empty placeholder stl returns nil so writeback is skipped" do
    File.write(@root.join("shapes/horn.stl"), "solid horn\nendsolid horn\n")
    assert_nil GeometryFingerprint.compute(add_asset!("horn.stl"))
  end

  private

  def add_asset!(filename)
    kind = File.extname(filename).delete(".").downcase
    @model.assets.create!(
      relative_path: filename,
      filename: filename,
      kind: kind,
      byte_size: File.size(@root.join("shapes", filename))
    )
  end
end
