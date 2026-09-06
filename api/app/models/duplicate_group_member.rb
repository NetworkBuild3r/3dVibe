class DuplicateGroupMember < ApplicationRecord
  belongs_to :duplicate_group
  belongs_to :asset, optional: true
  belongs_to :archive_member, optional: true
  belongs_to :vibe_model, optional: true

  validates :asset_id, uniqueness: { scope: :duplicate_group_id }, allow_nil: true
  validates :archive_member_id, uniqueness: { scope: :duplicate_group_id }, allow_nil: true
  validate :exactly_one_target

  def asset?
    asset_id.present?
  end

  def archive_member?
    archive_member_id.present?
  end

  def mergeable?
    asset? && !archive_member?
  end

  private

  def exactly_one_target
    return if asset_id.present? ^ archive_member_id.present?

    errors.add(:base, "exactly one of asset_id or archive_member_id is required")
  end
end
