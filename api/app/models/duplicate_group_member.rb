class DuplicateGroupMember < ApplicationRecord
  belongs_to :duplicate_group
  belongs_to :asset
  belongs_to :vibe_model, optional: true

  validates :asset_id, uniqueness: { scope: :duplicate_group_id }
end
