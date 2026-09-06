require "test_helper"

class DuplicateGroupMemberTest < ActiveSupport::TestCase
  def setup
    @library = Library.create!(name: "XOR", root_path: "/tmp/unused-xor")
    @model = @library.vibe_models.create!(folder_name: "kit", title: "Kit")
    @asset = @model.assets.create!(relative_path: "a.stl", filename: "a.stl", kind: "stl")
    @zip = @model.assets.create!(relative_path: "pack.zip", filename: "pack.zip", kind: "zip")
    @member = @zip.archive_members.create!(internal_path: "path/foo.stl", directory: false)
    @group = @library.duplicate_groups.create!(
      reason: DuplicateGroup::REASON_GEOMETRY,
      confidence: DuplicateGroup::CONFIDENCE_GEOMETRY,
      digest: "mesh:v1:x",
      status: DuplicateGroup::OPEN
    )
  end

  test "accepts exactly one of asset_id or archive_member_id" do
    loose = @group.duplicate_group_members.create!(asset: @asset, vibe_model: @model)
    assert loose.asset?
    assert loose.mergeable?

    inner = @group.duplicate_group_members.create!(archive_member: @member, vibe_model: @model)
    assert inner.archive_member?
    refute inner.mergeable?
  end

  test "rejects both or neither target" do
    neither = @group.duplicate_group_members.build
    refute neither.valid?
    assert_includes neither.errors[:base], "exactly one of asset_id or archive_member_id is required"

    both = @group.duplicate_group_members.build(asset: @asset, archive_member: @member)
    refute both.valid?
  end
end
