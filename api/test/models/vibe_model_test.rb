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
end
