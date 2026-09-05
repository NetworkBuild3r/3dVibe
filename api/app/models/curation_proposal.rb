class CurationProposal < ApplicationRecord
  PENDING = "pending"
  APPROVED = "approved"
  REJECTED = "rejected"
  STATUSES = [PENDING, APPROVED, REJECTED].freeze
  KINDS = %w[organize merge tag rename].freeze

  belongs_to :library
  belongs_to :reviewed_by, class_name: "User", optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :summary, presence: true

  scope :pending, -> { where(status: PENDING).order(created_at: :desc) }

  def pending?
    status == PENDING
  end
end
