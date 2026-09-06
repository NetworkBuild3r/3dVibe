require "test_helper"
require "fileutils"
require "zip"

class GeometryFingerprintTest < ActiveSupport::TestCase
  TRIANGLES = [
    [[0.0, 0.0, 0.0], [10.0, 0.0, 0.0], [0.0, 10.0, 0.0]],
    [[0.0, 0.0, 0.0], [0.0, 10.0, 0.0], [0.0, 0.0, 10.0]]
  ].freeze

  def setup
    @root = Rails.root.join("tmp/geo-fp-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(@root.join("widget"))
    @library = Library.create!(name: "Geo", root_path: @root.to_s)
    @model = @library.vibe_models.create!(folder_name: "widget", title: "Widget")
  end

  def teardown
    FileUtils.rm_rf(@root)
    %w[VIBE_GEO_MAX_BYTES VIBE_GEO_MAX_VERTS VIBE_GEO_MAX_SECONDS VIBE_GEO_QUANT].each do |key|
      ENV.delete(key)
    end
  end

  test "same mesh different bytes share a stable digest" do
    write_ascii_stl(@root.join("widget/a.stl"), TRIANGLES, name: "export-a")
    write_ascii_stl(@root.join("widget/b.stl"), TRIANGLES.reverse, name: "re-export", extra: true)
    write_binary_stl(@root.join("widget/c.stl"), TRIANGLES)
    write_obj(@root.join("widget/d.obj"), TRIANGLES)
    write_3mf(@root.join("widget/e.3mf"), TRIANGLES)

    a = create_asset!("a.stl", "stl")
    b = create_asset!("b.stl", "stl")
    c = create_asset!("c.stl", "stl")
    d = create_asset!("d.obj", "obj")
    e = create_asset!("e.3mf", "3mf")

    digests = [a, b, c, d, e].map { |asset| GeometryFingerprint.compute(asset) }
    assert digests.all? { |digest| digest.match?(/\Amesh:v1:[0-9a-f]{64}\z/) }
    assert_equal 1, digests.uniq.size
  end

  test "already-present digest is not recomputed" do
    write_ascii_stl(@root.join("widget/kept.stl"), TRIANGLES)
    asset = create_asset!("kept.stl", "stl", geometry_digest: "mesh:already")

    assert_nil GeometryFingerprint.compute(asset)
    assert_equal "already_present", GeometryFingerprint.new(asset).tap(&:compute).skip_reason
    assert_equal "mesh:already", asset.reload.geometry_digest
  end

  test "jail refusal skips without crashing" do
    missing = create_asset!("gone.stl", "stl")
    fingerprint = GeometryFingerprint.new(missing)
    assert_nil fingerprint.compute
    assert_equal "jail", fingerprint.skip_reason

    escape = @model.assets.create!(
      relative_path: "../etc/passwd",
      filename: "passwd",
      kind: "stl",
      byte_size: 20
    )
    denied = GeometryFingerprint.new(escape)
    assert_nil denied.compute
    assert_equal "jail", denied.skip_reason
  end

  test "non-mesh assets skip cleanly" do
    File.write(@root.join("widget/notes.txt"), "not a mesh")
    File.write(@root.join("widget/print.gcode"), "; gcode\nG1 X0\n")
    File.binwrite(@root.join("widget/preview.png"), "png")

    txt = create_asset!("notes.txt", "txt")
    gcode = create_asset!("print.gcode", "gcode")
    png = create_asset!("preview.png", "png")

    [txt, gcode, png].each do |asset|
      fingerprint = GeometryFingerprint.new(asset)
      assert_nil fingerprint.compute
      assert_equal "non_mesh", fingerprint.skip_reason
    end
  end

  test "size prefilter skips without opening a huge catalog size" do
    write_ascii_stl(@root.join("widget/ok.stl"), TRIANGLES)
    asset = create_asset!("ok.stl", "stl", byte_size: 90_000_000)
    ENV["VIBE_GEO_MAX_BYTES"] = "1024"

    fingerprint = GeometryFingerprint.new(asset)
    assert_nil fingerprint.compute
    assert_equal "too_large", fingerprint.skip_reason
  end

  test "on-disk size cap skips after jail resolve" do
    write_ascii_stl(@root.join("widget/ok.stl"), TRIANGLES)
    asset = create_asset!("ok.stl", "stl", byte_size: 10)
    ENV["VIBE_GEO_MAX_BYTES"] = "20"

    fingerprint = GeometryFingerprint.new(asset)
    assert_nil fingerprint.compute
    assert_equal "too_large", fingerprint.skip_reason
  end

  test "vertex budget skips instead of hashing a huge mesh" do
    write_ascii_stl(@root.join("widget/ok.stl"), TRIANGLES)
    asset = create_asset!("ok.stl", "stl")
    budget = GeometryBudget.new(max_bytes: 0, max_verts: 2, max_seconds: 0)

    fingerprint = GeometryFingerprint.new(asset, budget: budget)
    assert_nil fingerprint.compute
    assert_equal "too_many_verts", fingerprint.skip_reason
  end

  test "time budget skips mid-parse" do
    write_ascii_stl(@root.join("widget/ok.stl"), TRIANGLES)
    asset = create_asset!("ok.stl", "stl")
    now = 0.0
    budget = GeometryBudget.new(max_bytes: 0, max_verts: 0, max_seconds: 1, clock: -> { now })
    now = 5.0

    fingerprint = GeometryFingerprint.new(asset, budget: budget)
    assert_nil fingerprint.compute
    assert_equal "time", fingerprint.skip_reason
  end

  test "write-back apply sets assets.geometry_digest" do
    write_ascii_stl(@root.join("widget/ok.stl"), TRIANGLES)
    asset = create_asset!("ok.stl", "stl")
    digest = GeometryFingerprint.compute(asset)
    assert digest.present?

    GeometryWriteback.apply!(asset_id: asset.id, geometry_digest: digest)
    assert_equal digest, asset.reload.geometry_digest
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

  def write_ascii_stl(path, triangles, name: "part", extra: false)
    lines = ["solid #{name}"]
    lines << "  ; re-export comments and spacing" if extra
    triangles.each do |tri|
      lines << "  facet normal 0 0 1"
      lines << "    outer loop"
      tri.each { |v| lines << "      vertex #{v[0]} #{v[1]} #{v[2]}" }
      lines << "    endloop"
      lines << "  endfacet"
      lines << "" if extra
    end
    lines << "endsolid #{name}"
    File.write(path, lines.join("\n"))
  end

  def write_binary_stl(path, triangles)
    File.open(path, "wb") do |io|
      io.write("re-export binary".ljust(80, "\0"))
      io.write([triangles.size].pack("V"))
      triangles.each do |tri|
        io.write(([0.0, 0.0, 1.0] + tri.flatten).pack("e12"))
        io.write([0].pack("v"))
      end
    end
  end

  def write_obj(path, triangles)
    verts = []
    faces = triangles.map do |tri|
      tri.map do |vert|
        verts << vert unless verts.include?(vert)
        verts.index(vert) + 1
      end
    end
    body = +"# re-export materials ignored\nmtllib colors.mtl\n"
    verts.each { |v| body << "v #{v[0]} #{v[1]} #{v[2]} 1.0\n" }
    body << "vn 0 0 1\n"
    faces.each { |f| body << "f #{f[0]}//1 #{f[1]}//1 #{f[2]}//1\n" }
    File.write(path, body)
  end

  def write_3mf(path, triangles)
    verts = []
    faces = triangles.map do |tri|
      tri.map do |vert|
        verts << vert unless verts.include?(vert)
        verts.index(vert)
      end
    end
    xml = +"<model unit=\"millimeter\"><resources><object id=\"1\" type=\"model\"><mesh><vertices>"
    verts.each { |v| xml << %(<vertex x="#{v[0]}" y="#{v[1]}" z="#{v[2]}"/>) }
    xml << "</vertices><triangles>"
    faces.each { |f| xml << %(<triangle v1="#{f[0]}" v2="#{f[1]}" v3="#{f[2]}"/>) }
    xml << "</triangles></mesh></object></resources>"
    xml << '<build><item objectid="1" transform="1 0 0 0 1 0 0 0 1 99 0 0"/></build></model>'
    Zip::File.open(path.to_s, Zip::File::CREATE) do |zip|
      zip.get_output_stream("3D/3dmodel.model") { |io| io.write(xml) }
    end
  end
end
