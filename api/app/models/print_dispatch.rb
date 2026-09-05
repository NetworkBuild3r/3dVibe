class PrintDispatch < ApplicationRecord
  belongs_to :vibe_model, optional: true
  belongs_to :asset, optional: true
  belongs_to :requested_by, class_name: "User"

  STATUSES = %w[queued accepted rejected unavailable].freeze

  validates :status, inclusion: { in: STATUSES }
end
