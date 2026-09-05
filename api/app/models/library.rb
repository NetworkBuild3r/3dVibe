class Library < ApplicationRecord
  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :vibe_models, dependent: :destroy
  has_many :scan_cursors, dependent: :destroy
  has_many :invites, dependent: :destroy
  has_many :curation_proposals, dependent: :destroy
  has_many :library_uploads, dependent: :destroy

  validates :name, presence: true
  validates :root_path, presence: true

  def owner
    memberships.find_by(role: Membership::OWNER)&.user
  end
end
