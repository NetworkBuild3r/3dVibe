class Membership < ApplicationRecord
  OWNER = "owner"
  FRIEND = "friend"
  ROLES = [OWNER, FRIEND].freeze

  belongs_to :user
  belongs_to :library

  validates :role, inclusion: { in: ROLES }
  validates :user_id, uniqueness: { scope: :library_id }

  def owner?
    role == OWNER
  end
end
