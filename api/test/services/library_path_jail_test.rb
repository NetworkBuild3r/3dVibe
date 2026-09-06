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

  test "model folders must stay first-level" do
    assert_equal "dragon-kit", @jail.normalize_model_folder("dragon-kit")
    assert_raises(ArgumentError) { @jail.normalize_model_folder("kits/dragon") }
    assert_raises(ArgumentError) { @jail.normalize_model_folder("../etc") }
  end
end
