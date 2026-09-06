require "test_helper"

class CreatorHintTest < ActiveSupport::TestCase
  test "uses a known pack-style prefix across titles" do
    dragon = CreatorHint.parse("Mz4250 - Dragon Knight")
    skeleton = CreatorHint.parse("Mz4250 - Skeleton")
    assert_equal "mz4250", dragon.slug
    assert_equal "Mz4250", dragon.name
    assert_equal Creator::SOURCE_NFS, dragon.source
    assert_equal dragon.slug, skeleton.slug
  end

  test "splits a generic Creator - Title pack and falls back to the first-level folder" do
    pack = CreatorHint.parse("Some Artist - Cool Model")
    assert_equal "some-artist", pack.slug
    assert_equal "Some Artist", pack.name

    folder = CreatorHint.parse("signal-horn")
    assert_equal "signal-horn", folder.slug
    assert_equal "Signal Horn", folder.name
  end

  test "upserts one creator row and does not create shelves" do
    first = CreatorHint.upsert!("Printable Scenery - Watchtower")
    second = CreatorHint.upsert!("printable-scenery")
    assert_equal first.id, second.id
    assert_equal "printable-scenery", first.slug
    assert_equal 0, BookmarkFolder.count
  end
end
