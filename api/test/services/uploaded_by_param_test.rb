require "test_helper"

class UploadedByParamTest < ActiveSupport::TestCase
  def setup
    @owner = create_owner!
  end

  test "blank or omitted is All" do
    assert_nil UploadedByParam.resolve(nil, current_user: @owner)
    assert_nil UploadedByParam.resolve("", current_user: @owner)
    assert_nil UploadedByParam.resolve("  ", current_user: @owner)
    assert_nil UploadedByParam.from_params({}, current_user: @owner)
    assert_nil UploadedByParam.from_params({ uploaded_by: "" }, current_user: @owner)
    assert_nil UploadedByParam.from_params({ uploaded_by_id: "" }, current_user: @owner)
  end

  test "me resolves to the authenticated current user only" do
    friend = create_user!(email: "pal@example.test")
    assert_equal @owner.id, UploadedByParam.resolve("me", current_user: @owner)
    assert_equal @owner.id, UploadedByParam.resolve("ME", current_user: @owner)
    assert_equal friend.id, UploadedByParam.resolve("me", current_user: friend)
    refute_equal friend.id, UploadedByParam.resolve("me", current_user: @owner)
  end

  test "numeric user_id is passed through" do
    assert_equal 42, UploadedByParam.resolve("42", current_user: @owner)
    assert_equal 42, UploadedByParam.from_params({ uploaded_by_id: "42" }, current_user: @owner)
  end

  test "uploaded_by wins over the uploaded_by_id alias" do
    assert_equal @owner.id, UploadedByParam.from_params(
      { uploaded_by: "me", uploaded_by_id: "99" },
      current_user: @owner
    )
  end

  test "invalid tokens are unmatched so callers return empty not All" do
    assert_equal UploadedByParam::NONE, UploadedByParam.resolve("friend", current_user: @owner)
    assert_equal UploadedByParam::NONE, UploadedByParam.resolve("abc", current_user: @owner)
    assert_equal UploadedByParam::NONE, UploadedByParam.resolve("-1", current_user: @owner)
  end
end
