class Printer < ApplicationRecord
  MOCK = "mock"
  SDCP = "sdcp"
  PROTOCOL_TYPES = [MOCK, SDCP].freeze

  belongs_to :library
  has_many :print_dispatches, dependent: :nullify

  validates :name, presence: true, uniqueness: { scope: :library_id }
  validates :host, presence: true, format: {
    with: /\A[A-Za-z0-9][A-Za-z0-9._\-:]*\z/,
    message: "must be a hostname or IP (no URL)"
  }
  validates :protocol_type, inclusion: { in: PROTOCOL_TYPES }

  scope :enabled, -> { where(enabled: true) }
  scope :by_name, -> { order(:name) }

  def mock?
    protocol_type == MOCK
  end

  def sdcp?
    protocol_type == SDCP
  end
end
