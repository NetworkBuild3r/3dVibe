class DuplicateReview < ApplicationRecord
  KEEP = "keep"
  DISMISS = "dismiss"
  MERGE = "merge"
  DECISIONS = [KEEP, DISMISS, MERGE].freeze

  belongs_to :duplicate_group
  belongs_to :user

  validates :decision, inclusion: { in: DECISIONS }

  def as_api
    {
      id: id,
      duplicate_group_id: duplicate_group_id,
      user_id: user_id,
      decision: decision,
      payload: payload,
      created_at: created_at
    }
  end
end
