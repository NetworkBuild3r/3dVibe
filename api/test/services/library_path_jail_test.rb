require "test_helper"
require "fileutils"

class LibraryPathJailTest < ActiveSupport::TestCase
  def setup
    @root = Rails.root.join("tmp/jail-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(@root)
    @jail = LibraryPathJail.new(@root)
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  test "joins a folder and relative path inside the root" do
    path = @jail.join("dragon-kit", "parts/head.stl")
    assert_equal @root.join("dragon-kit/parts/head.stl").to_s, path.to_s
  end

  test "rejects traversal and hidden segments" do
    assert_raises(ArgumentError) { @jail.normalize_folder("../etc") }
    assert_raises(ArgumentError) { @jail.normalize_relative("foo/../passwd") }
    assert_raises(ArgumentError) { @jail.normalize_folder(".hidden") }
    assert_raises(ArgumentError) { @jail.normalize_relative(".vibe-incoming/x") }
  end

  test "resolve_jailed accepts a jail-relative file path" do
    FileUtils.mkdir_p(@root.join("CreatorPack/model"))
    File.write(@root.join("CreatorPack/model/preview.png"), "png")
    path = @jail.resolve_jailed("CreatorPack/model/preview.png")
    assert_equal @root.join("CreatorPack/model/preview.png").realpath.to_s, path.to_s
    assert_raises(ArgumentError) { @jail.resolve_jailed("CreatorPack") }
    assert_raises(ArgumentError) { @jail.resolve_jailed("../etc/passwd") }
  end

  test "resolve_file requires a regular file inside the root" do
    FileUtils.mkdir_p(@root.join("signal-horn"))
    File.write(@root.join("signal-horn/horn.stl"), "solid x\n")
    path = @jail.resolve_file("signal-horn", "horn.stl")
    assert_equal @root.join("signal-horn/horn.stl").realpath.to_s, path.to_s
    assert_raises(ArgumentError) { @jail.resolve_file("signal-horn", "missing.stl") }
    assert_raises(ArgumentError) { @jail.resolve_file("signal-horn", "../../etc/passwd") }
  end

  test "model folders must stay first-level" do
    assert_equal "dragon-kit", @jail.normalize_model_folder("dragon-kit")
    assert_raises(ArgumentError) { @jail.normalize_model_folder("kits/dragon") }
    assert_raises(ArgumentError) { @jail.normalize_model_folder("../etc") }
  end
end
