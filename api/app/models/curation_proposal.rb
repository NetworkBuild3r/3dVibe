class CurationProposal < ApplicationRecord
  PENDING = "pending"
  APPROVED = "approved"
  REJECTED = "rejected"
  STATUSES = [PENDING, APPROVED, REJECTED].freeze
  KINDS = %w[organize merge tag rename move].freeze

  belongs_to :library
  belongs_to :reviewed_by, class_name: "User", optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :summary, presence: true

  scope :pending, -> { where(status: PENDING).order(created_at: :desc) }

  def pending?
    status == PENDING
  end

  def approved?
    status == APPROVED
  end

  def rejected?
    status == REJECTED
  end

  def applied?
    applied_at.present?
  end

  def tag?
    kind == "tag"
  end

  def rename?
    kind == "rename"
  end

  def move?
    kind == "move"
  end

  def merge?
    kind == "merge"
  end

  def organize?
    kind == "organize"
  end

  def payload_hash
    (payload.presence || {}).stringify_keys
  end

  def destination_folder
    payload_hash["to"].presence || payload_hash["destination_folder"].presence
  end

  def filesystem_change?
    rename? || move? || merge? || (organize? && destination_folder.present?)
  end

  def immediate_apply?
    approved? && !filesystem_change?
  end
end
