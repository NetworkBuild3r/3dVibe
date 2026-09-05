class Membership < ApplicationRecord
  OWNER = "owner"
  CONTRIBUTOR = "contributor"
  VIEWER = "viewer"
  ROLES = [OWNER, CONTRIBUTOR, VIEWER].freeze
  UPLOAD_ROLES = [OWNER, CONTRIBUTOR].freeze
  INVITABLE_ROLES = [CONTRIBUTOR, VIEWER].freeze

  belongs_to :user
  belongs_to :library

  validates :role, inclusion: { in: ROLES }
  validates :user_id, uniqueness: { scope: :library_id }

  def owner?
    role == OWNER
  end

  def contributor?
    role == CONTRIBUTOR
  end

  def viewer?
    role == VIEWER
  end

  def can_upload?
    UPLOAD_ROLES.include?(role)
  end
end
