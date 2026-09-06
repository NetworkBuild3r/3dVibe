class PrintDispatch < ApplicationRecord
  belongs_to :library, optional: true
  belongs_to :printer, optional: true
  belongs_to :vibe_model, optional: true
  belongs_to :asset, optional: true
  belongs_to :requested_by, class_name: "User"

  QUEUED = "queued"
  SENDING = "sending"
  PRINTING = "printing"
  SUCCEEDED = "succeeded"
  FAILED = "failed"
  CANCELLED = "cancelled"
  UNAVAILABLE = "unavailable"

  ACTIVE = [QUEUED, SENDING, PRINTING].freeze
  TERMINAL = [SUCCEEDED, FAILED, CANCELLED].freeze
  STATUSES = (ACTIVE + TERMINAL + [UNAVAILABLE]).freeze

  validates :status, inclusion: { in: STATUSES }
  validates :progress, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }

  scope :recent, -> { order(created_at: :desc) }
  scope :active, -> { where(status: ACTIVE) }

  def terminal?
    TERMINAL.include?(status)
  end

  def active?
    ACTIVE.include?(status)
  end

  def mark_sending!
    return if terminal?

    update!(status: SENDING, progress: [progress, 5].max, started_at: started_at || Time.current)
  end

  def mark_printing!(progress_value = 25)
    return if terminal?

    update!(status: PRINTING, progress: progress_value.to_i.clamp(0, 99), started_at: started_at || Time.current)
  end

  def mark_succeeded!(note_text = nil)
    return if terminal?

    update!(
      status: SUCCEEDED,
      progress: 100,
      finished_at: Time.current,
      note: note_text.presence || note.presence || "Print finished."
    )
  end

  def fail_soft!(message)
    return if terminal?

    text = message.to_s.truncate(500)
    update!(
      status: FAILED,
      error_message: text,
      finished_at: Time.current,
      note: "Print failed: #{text}"
    )
  end

  def cancel!(note_text = "Cancelled")
    return false if terminal?

    update!(status: CANCELLED, finished_at: Time.current, note: note_text)
    true
  end
end
