require "test_helper"

class VibeModelTest < ActiveSupport::TestCase
  ASSET_DETAIL_KEYS = %w[
    id filename relative_path kind byte_size content_digest geometry_digest
    archive mesh archive_member_count archive_truncated archive_support
    mergeable uploaded_by
  ].freeze

  def setup
    @owner = create_owner!
    @friend = create_user!(email: "friend@example.test")
    @library = Library.create!(name: "Detail", root_path: "/tmp/vibe-model-detail-#{SecureRandom.hex(4)}")
    @model = @library.vibe_models.create!(
      folder_name: "kit",
      title: "Kit",
      folder_mtime: Time.utc(2026, 9, 1, 12, 0, 0),
      uploaded_by: @owner
    )
    @readme = @model.assets.create!(
      relative_path: "readme.txt",
      filename: "readme.txt",
      kind: "file",
      byte_size: 12,
      content_digest: "sha256:readme"
    )
    @zip = @model.assets.create!(
      relative_path: "pack.zip",
      filename: "pack.zip",
      kind: "zip",
      byte_size: 64,
      content_digest: "sha256:pack",
      geometry_digest: nil,
      archive_truncated: true,
      archive_support: Asset::ARCHIVE_SUPPORT_FULL,
      uploaded_by: @owner
    )
    @zip.archive_members.create!(internal_path: "path/foo.stl", directory: false)
    @zip.archive_members.create!(internal_path: "docs/", directory: true)
    @merge = @library.model_merges.create!(
      target_vibe_model: @model,
      kind: "assets",
      performed_by: @owner,
      parts: [{ "folder_name" => "loose" }],
      result: { "moved" => 1 }
    )
    @owner.likes.create!(vibe_model: @model)
    folder = @owner.bookmark_folders.create!(name: "Weekend")
    folder.bookmarks.create!(user: @owner, vibe_model: @model)
  end

  test "detail_payload extends the card with folder_mtime, merges, and on-disk assets" do
    payload = VibeModel.detail_payload(@model, viewer: @owner)

    assert_equal @model.id, payload[:id]
    assert_equal @model.title, payload[:title]
    assert_equal @model.folder_mtime, payload[:folder_mtime]
    assert_equal true, payload[:liked]
    assert_equal 1, payload[:like_count]
    assert_equal [@owner.bookmark_folders.first.id], payload[:bookmark_folder_ids]
    assert_equal true, payload[:merged]

    assert_equal 1, payload[:merges].size
    assert_equal @merge.as_api, payload[:merges].first

    assert_equal %w[pack.zip readme.txt], payload[:assets].map { |row| row[:filename] }
    pack = payload[:assets].first
    assert_equal ASSET_DETAIL_KEYS, pack.keys.map(&:to_s)
    assert_equal true, pack[:archive]
    assert_equal false, pack[:mesh]
    assert_equal 2, pack[:archive_member_count]
    assert_equal true, pack[:archive_truncated]
    assert_equal Asset::ARCHIVE_SUPPORT_FULL, pack[:archive_support]
    assert_equal true, pack[:mergeable]
    assert_equal({ id: @owner.id, display_name: @owner.display_name }, pack[:uploaded_by])

    readme = payload[:assets].last
    assert_equal false, readme[:archive]
    assert_nil readme[:uploaded_by]
    assert_equal true, readme[:mergeable]
  end

  test "detail_payload viewer fields stay personal" do
    payload = VibeModel.detail_payload(@model, viewer: @friend)

    assert_equal false, payload[:liked]
    assert_equal 1, payload[:like_count]
    assert_equal [], payload[:bookmark_folder_ids]
    assert_equal true, payload[:merged]
  end
end
