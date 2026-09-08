require "test_helper"

class VibeModelTest < ActiveSupport::TestCase
  def setup
    @owner = create_owner!
    @friend = create_user!(email: "friend@example.test")
    @library = create_shared_library!(owner: @owner, contributor: @friend)
    @model = @library.vibe_models.create!(
      folder_name: "horn",
      title: "Horn",
      folder_mtime: Time.utc(2026, 1, 2, 12, 0, 0)
    )
    @asset = @model.assets.create!(
      relative_path: "horn.stl",
      filename: "horn.stl",
      kind: "stl",
      byte_size: 12,
      content_digest: "abc",
      uploaded_by: @owner
    )
  end

  test "detail_payload is the shared model+assets shape used by show, duplicates, and extract" do
    @owner.likes.create!(vibe_model: @model)
    payload = VibeModel.detail_payload(@model, viewer: @owner)

    assert_equal @model.id, payload[:id]
    assert_equal "Horn", payload[:title]
    assert_equal @model.folder_mtime, payload[:folder_mtime]
    assert_equal true, payload[:liked]
    assert_equal 1, payload[:like_count]
    assert_equal [], payload[:bookmark_folder_ids]
    assert_equal [], payload[:merges]
    assert_equal 1, payload[:assets].size

    asset = payload[:assets].first
    assert_equal @asset.id, asset[:id]
    assert_equal "horn.stl", asset[:filename]
    assert_equal "horn.stl", asset[:relative_path]
    assert_equal "stl", asset[:kind]
    assert_equal 12, asset[:byte_size]
    assert_equal "abc", asset[:content_digest]
    assert_nil asset[:geometry_digest]
    assert_equal false, asset[:archive]
    assert_equal true, asset[:mesh]
    assert_equal 0, asset[:archive_member_count]
    assert_equal true, asset[:mergeable]
    assert_equal({ id: @owner.id, display_name: @owner.display_name }, asset[:uploaded_by])
  end

  test "detail_payload viewer fields stay personal" do
    @owner.likes.create!(vibe_model: @model)
    friend_payload = VibeModel.detail_payload(@model, viewer: @friend)

    refute friend_payload[:liked]
    assert_equal 1, friend_payload[:like_count]
    assert_equal [], friend_payload[:bookmark_folder_ids]
  end

  test "on-disk assets are mergeable in the shared detail shape" do
    assert_equal true, VibeModel.asset_detail(@asset)[:mergeable]
  end

  test "folder_name accepts Category/Pack and denormalizes category" do
    pack = @library.vibe_models.create!(
      folder_name: "Anime/AOT-ErenXArmored",
      title: "AOT Eren X Armored"
    )

    assert_equal "Anime/AOT-ErenXArmored", pack.folder_name
    assert_equal "Anime", pack.category
    assert_equal "Anime", pack.as_card[:category]
    assert_includes VibeModel.in_category("Anime"), pack
    refute_includes VibeModel.in_category("DC"), pack
  end

  test "first-level folder_name stays unique per flat library" do
    dup = @library.vibe_models.build(folder_name: "horn", title: "Horn copy")
    refute dup.valid?
    assert_includes dup.errors[:folder_name], "has already been taken"

    other = create_shared_library!(
      owner: @owner,
      name: "Other pile",
      root_path: "/tmp/other-#{SecureRandom.hex(4)}",
      layout_mode: Library::LAYOUT_FLAT
    )
    twin = other.vibe_models.create!(folder_name: "horn", title: "Horn elsewhere")
    assert_equal "horn", twin.category
    assert_equal other.id, twin.library_id
  end

  test "keeps an existing mega-row and allows a sibling pack path" do
    mega = @library.vibe_models.create!(folder_name: "Anime", title: "Anime")
    pack = @library.vibe_models.create!(folder_name: "Anime/AOT-ErenXArmored", title: "Eren")

    assert_equal "Anime", mega.reload.folder_name
    assert_equal "Anime", mega.category
    assert_equal "Anime/AOT-ErenXArmored", pack.folder_name
    assert_equal 1, @library.vibe_models.where(folder_name: "Anime").count
  end

  test "rejects folder_name with .. absolute paths or NUL" do
    {
      "../escape" => "must not contain ..",
      "Anime/../etc" => "must not contain ..",
      "/Anime/AOT-ErenXArmored" => "must be a library-relative path",
      "\\Anime\\Pack" => "must be a library-relative path",
      "C:/Anime/Pack" => "must be a library-relative path"
    }.each do |name, message|
      model = @library.vibe_models.build(folder_name: name, title: "Bad")
      refute model.valid?, name
      assert_includes model.errors[:folder_name], message, name
    end

    model = @library.vibe_models.build(title: "Bad")
    begin
      model.folder_name = "safe\0pack"
      refute model.valid?
      assert_includes model.errors[:folder_name], "contains a NUL byte"
    rescue ArgumentError => error
      assert_match(/null byte/i, error.message)
    end
  end

  test "unique index allows Category/Pack but not a duplicate pack path" do
    @library.vibe_models.create!(folder_name: "Movie TV/Reinhardt", title: "Reinhardt")
    clash = @library.vibe_models.build(folder_name: "Movie TV/Reinhardt", title: "Again")
    refute clash.valid?
    assert_includes clash.errors[:folder_name], "has already been taken"

    sibling = @library.vibe_models.create!(folder_name: "Movie TV/D.Va", title: "D.Va")
    assert_equal "Movie TV", sibling.category
  end
end

