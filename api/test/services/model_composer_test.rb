require "test_helper"
require "fileutils"
require "zip"

class ModelComposerTest < ActiveSupport::TestCase
  def setup
    @root = Rails.root.join("tmp/compose-lib-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(@root.join("signal-horn"))
    File.write(@root.join("signal-horn/horn.stl"), "solid horn\nendsolid horn\n")
    File.write(@root.join("signal-horn/readme.txt"), "horn notes")
    FileUtils.mkdir_p(@root.join("crate"))
    Zip::File.open(@root.join("crate/parts.zip"), Zip::File::CREATE) do |zip|
      zip.get_output_stream("lid.stl") { |io| io.write("solid lid\nendsolid lid\n") }
    end
    File.write(@root.join("crate/box.stl"), "solid box\nendsolid box\n")

    @owner = create_owner!
    @library = Library.create!(name: "Compose pile", root_path: @root.to_s)
    Membership.create!(user: @owner, library: @library, role: Membership::OWNER)
    LibraryScanner.new(@library).scan!
    @horn = @library.vibe_models.find_by!(folder_name: "signal-horn")
    @crate = @library.vibe_models.find_by!(folder_name: "crate")
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  test "merge models moves files on disk and updates the index" do
    composer = ModelComposer.new(@library, performed_by: @owner)
    record = composer.merge!(source_ids: [@horn.id], target_id: @crate.id)

    refute @library.vibe_models.exists?(id: @horn.id)
    target = @library.vibe_models.find(@crate.id)
    assert File.file?(@root.join("crate/signal-horn/horn.stl"))
    refute File.exist?(@root.join("signal-horn"))
    assert target.assets.exists?(relative_path: "signal-horn/horn.stl")
    assert record.parts.first["files"].include?("signal-horn/horn.stl")
    refute record.split?
  end

  test "merge selected archives and stls without reading archive bytes" do
    zip = @crate.assets.find_by!(filename: "parts.zip")
    stl = @horn.assets.find_by!(filename: "horn.stl")
    original_zip = File.binread(@root.join("crate/parts.zip"))

    record = ModelComposer.new(@library, performed_by: @owner).merge!(
      asset_ids: [zip.id, stl.id],
      title: "Horn kit"
    )

    target = @library.vibe_models.find(record.target_vibe_model_id)
    assert_equal "Horn kit", target.title
    assert File.file?(@root.join("#{target.folder_name}/crate/parts.zip"))
    assert File.file?(@root.join("#{target.folder_name}/signal-horn/horn.stl"))
    assert_equal original_zip, File.binread(@root.join("#{target.folder_name}/crate/parts.zip"))
    assert target.assets.exists?(filename: "parts.zip")
    assert target.assets.exists?(filename: "horn.stl")
  end

  test "split restores first-level folders from a recorded merge" do
    composer = ModelComposer.new(@library, performed_by: @owner)
    record = composer.merge!(source_ids: [@horn.id], target_id: @crate.id)
    target = @library.vibe_models.find(@crate.id)

    split = composer.split!(target, merge_id: record.id)
    assert split.split?
    restored = @library.vibe_models.find_by!(folder_name: "signal-horn")
    assert File.file?(@root.join("signal-horn/horn.stl"))
    refute File.exist?(@root.join("crate/signal-horn/horn.stl"))
    assert restored.assets.exists?(filename: "horn.stl")
  end

  test "merge stays inside the path jail" do
    escaped = @horn.assets.create!(relative_path: "../outside.stl", filename: "outside.stl", kind: "stl")
    File.write(@root.join("outside.stl"), "solid escape\nendsolid escape\n")

    assert_raises(ArgumentError) do
      ModelComposer.new(@library, performed_by: @owner).merge!(
        asset_ids: [escaped.id],
        title: "Nope"
      )
    end
    assert File.file?(@root.join("outside.stl"))
  end
end
