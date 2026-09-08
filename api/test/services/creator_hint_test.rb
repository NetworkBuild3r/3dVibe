require "test_helper"
require "fileutils"

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
    assert_equal CreatorHint::AUTHORITY_PACK_PREFIX, pack.authority

    folder = CreatorHint.parse("signal-horn")
    assert_equal "signal-horn", folder.slug
    assert_equal "Signal Horn", folder.name
  end

  test "Anime/Hero-Figure does not set creator to Anime from the first-level shelf" do
    hint = CreatorHint.parse("Anime/Hero-Figure")
    assert_nil hint
    assert_nil CreatorHint.upsert!("Anime/Hero-Figure")
  end

  test "datapackage creator and keywords beat pack prefix and category" do
    root = Rails.root.join("tmp/hint-dp-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(root)
    File.write(
      root.join("datapackage.json"),
      JSON.generate(
        "creator" => "Studio X",
        "keywords" => %w[attack-on-titan eren],
        "contributors" => [{ "title" => "Ignored", "roles" => ["creator"] }]
      )
    )

    hint = CreatorHint.parse("Anime/Mz4250 - Hero-Figure", pack_root: root.to_s)
    assert_equal "studio-x", hint.slug
    assert_equal "Studio X", hint.name
    assert_equal %w[attack-on-titan eren], hint.keywords
    assert_equal CreatorHint::AUTHORITY_DATAPACKAGE, hint.authority
    assert_equal Creator::SOURCE_NFS, hint.source
  ensure
    FileUtils.rm_rf(root) if defined?(root) && root
  end

  test "datapackage contributors roles creator is used when creator field is absent" do
    root = Rails.root.join("tmp/hint-dp-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(root)
    File.write(
      root.join("datapackage.json"),
      JSON.generate("keywords" => ["chibi"], "contributors" => [{ "title" => "Loot Studios", "roles" => ["creator"] }])
    )

    hint = CreatorHint.parse("Anime/Hero-Figure", pack_root: root.to_s)
    assert_equal "loot-studios", hint.slug
    assert_equal "Loot Studios", hint.name
    assert_equal ["chibi"], hint.keywords
  ensure
    FileUtils.rm_rf(root) if defined?(root) && root
  end

  test "Category/Pack Creator - Title prefix still hints the pack creator" do
    hint = CreatorHint.parse("Anime/Some Artist - Cool Model")
    assert_equal "some-artist", hint.slug
    assert_equal "Some Artist", hint.name
    assert_equal CreatorHint::AUTHORITY_PACK_PREFIX, hint.authority
  end

  test "category is a weak hint only when it is not a genre shelf" do
    weak = CreatorHint.parse("B3dserk/SomeModel")
    assert_equal "b3dserk", weak.slug
    assert_equal "B3dserk", weak.name
    assert_equal CreatorHint::AUTHORITY_CATEGORY, weak.authority

    known = CreatorHint.parse("Titan Forge/Cool Mini")
    assert_equal "titan-forge", known.slug
    assert_equal CreatorHint::AUTHORITY_CATEGORY, known.authority
  end

  test "rejects a pack_root that contains .." do
    assert_raises(ArgumentError) do
      CreatorHint.parse("Anime/Hero-Figure", pack_root: "/tmp/hint/../etc")
    end
  end

  test "upserts one creator row and does not create shelves" do
    first = CreatorHint.upsert!("Printable Scenery - Watchtower")
    second = CreatorHint.upsert!("printable-scenery")
    assert_equal first.id, second.id
    assert_equal "printable-scenery", first.slug
    assert_equal 0, BookmarkFolder.count
  end
end
