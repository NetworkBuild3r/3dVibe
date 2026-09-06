class Library < ApplicationRecord
  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :vibe_models, dependent: :destroy
  has_many :scan_cursors, dependent: :destroy
  has_many :scan_runs, dependent: :destroy
  has_many :invites, dependent: :destroy
  has_many :curation_proposals, dependent: :destroy
  has_many :library_uploads, dependent: :destroy
  has_many :printers, dependent: :destroy
  has_many :print_dispatches, dependent: :nullify

  validates :name, presence: true
  validates :root_path, presence: true

  def owner
    memberships.find_by(role: Membership::OWNER)&.user
  end

  def latest_scan_run
    scan_runs.recent.first
  end
end
