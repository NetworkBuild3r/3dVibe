require "test_helper"

class LibraryTest < ActiveSupport::TestCase
  test "defaults layout_mode to category_model and accepts flat fixtures" do
    library = Library.create!(name: "Live", root_path: "/tmp/layout-#{SecureRandom.hex(4)}")
    assert_equal Library::LAYOUT_CATEGORY_MODEL, library.layout_mode

    flat = Library.create!(
      name: "Fixture",
      root_path: "/tmp/layout-flat-#{SecureRandom.hex(4)}",
      layout_mode: Library::LAYOUT_FLAT
    )
    assert_equal Library::LAYOUT_FLAT, flat.layout_mode

    library.layout_mode = "nested"
    refute library.valid?
    assert_includes library.errors[:layout_mode], "is not included in the list"
  end

  test "scan cursor path_prefix stores Category/Pack not basename-only" do
    library = Library.create!(name: "Cursors", root_path: "/tmp/cursor-#{SecureRandom.hex(4)}")
    cursor = library.scan_cursors.create!(path_prefix: "Anime/AOT-ErenXArmored")
    assert_equal "Anime/AOT-ErenXArmored", cursor.path_prefix

    clash = library.scan_cursors.build(path_prefix: "Anime/AOT-ErenXArmored")
    refute clash.valid?
    assert_includes clash.errors[:path_prefix], "has already been taken"

    sibling = library.scan_cursors.create!(path_prefix: "Anime/Levi")
    assert_equal "Anime/Levi", sibling.path_prefix
  end
end
