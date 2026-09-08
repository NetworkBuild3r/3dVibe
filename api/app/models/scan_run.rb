class ScanRun < ApplicationRecord
  QUEUED = "queued"
  RUNNING = "running"
  COMPLETED = "completed"
  BUDGETED = "budgeted"
  FAILED = "failed"

  STATUSES = [QUEUED, RUNNING, COMPLETED, BUDGETED, FAILED].freeze

  PHASE_WALK = "walk"
  PHASE_PRUNE = "prune"
  PHASE_DONE = "done"

  TRIGGER_API = "api"
  TRIGGER_RAKE = "rake"
  TRIGGER_SCHEDULED = "scheduled"
  TRIGGER_UPLOAD = "upload"
  TRIGGER_CURATION = "curation"
  TRIGGER_TARGETED = "targeted"
  TRIGGER_INLINE = "inline"
  TRIGGER_RESUME = "resume"
  TRIGGER_JOB = "job"
  TRIGGER_REBUILD = "rebuild"

  belongs_to :library
  belongs_to :triggered_by, class_name: "User", optional: true

  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(Arel.sql("COALESCE(started_at, created_at) DESC, id DESC")) }
  scope :active, -> { where(status: [QUEUED, RUNNING, BUDGETED]) }
  scope :for_prefix, lambda { |prefix|
    prefix.present? ? where(path_prefix: prefix) : where(path_prefix: [nil, ""])
  }

  def self.claim!(library, path_prefix:, trigger:, user: nil)
    prefix = path_prefix.to_s.presence
    library.with_lock do
      scope = library.scan_runs.for_prefix(prefix)
      running = scope.where(status: RUNNING).order(:id).last
      return nil if running && !running.stale_lock?

      budgeted = scope.where(status: BUDGETED).order(:id).last
      queued = scope.where(status: QUEUED).order(:id).last
      existing = budgeted || queued || running
      if existing
        scope.where(status: QUEUED).where.not(id: existing.id).update_all(
          status: COMPLETED,
          last_error: "merged into run #{existing.id}",
          finished_at: Time.current,
          updated_at: Time.current
        )
        existing.update!(
          status: RUNNING,
          started_at: existing.started_at || Time.current,
          finished_at: nil,
          budget_exhausted: false,
          last_error: nil
        )
        existing
      else
        library.scan_runs.create!(
          status: RUNNING,
          trigger: trigger.presence || (prefix ? TRIGGER_TARGETED : TRIGGER_JOB),
          path_prefix: prefix,
          triggered_by: user,
          phase: PHASE_WALK,
          started_at: Time.current
        )
      end
    end
  end

  def stale_lock?
    stamp = [updated_at, started_at].compact.max
    stamp.blank? || stamp < ScanSettings::STALE_RUN_AFTER.ago
  end

  def running?
    status == RUNNING
  end

  def queued?
    status == QUEUED
  end

  def budgeted?
    status == BUDGETED
  end

  def completed?
    status == COMPLETED
  end

  def failed?
    status == FAILED
  end

  def mark_budgeted!(reason: nil)
    message = ["budget exhausted", reason].compact.join(": ")
    update!(
      status: BUDGETED,
      budget_exhausted: true,
      last_error: last_error.presence || message,
      finished_at: Time.current
    )
  end

  def mark_completed!
    update!(
      status: COMPLETED,
      phase: PHASE_DONE,
      budget_exhausted: false,
      resume_after: nil,
      finished_at: Time.current
    )
  end

  def fail!(error)
    update!(
      status: FAILED,
      finished_at: Time.current,
      error_count: error_count + 1,
      last_error: "#{error.class}: #{error.message}".truncate(2_000)
    )
  end

  def record_error(context, error)
    self.error_count += 1
    self.last_error = "#{context}: #{error.class}: #{error.message}".truncate(2_000)
    save!
  end

  def as_api
    {
      id: id,
      status: status,
      trigger: trigger,
      phase: phase,
      path_prefix: safe_pack_path(path_prefix),
      started_at: started_at,
      finished_at: finished_at,
      resume_after: safe_last_pack_path,
      folders_seen: folders_seen,
      folders_indexed: folders_indexed,
      folders_skipped: folders_skipped,
      packs_indexed: folders_indexed,
      running: queued? || running?,
      last_pack_path: safe_last_pack_path,
      files_seen: files_seen,
      files_changed: files_changed,
      pruned_count: pruned_count,
      error_count: error_count,
      deep_walks: deep_walks,
      budget_exhausted: budget_exhausted,
      last_error: last_error,
      budgets: ScanSettings.budgets_as_api,
      resume: resume_as_api,
      updated_at: updated_at
    }
  end

  def self.idle_as_api
    {
      status: "idle",
      packs_indexed: 0,
      running: false,
      last_pack_path: nil,
      budgets: ScanSettings.budgets_as_api,
      resume: nil
    }
  end

  def resume_as_api
    cursor = resume_cursor
    path = safe_relative_path(cursor&.resume_relative_path)
    after = safe_last_pack_path
    prefix = safe_pack_path(cursor&.path_prefix) || after || safe_pack_path(path_prefix)
    return nil if after.blank? && path.blank?

    {
      resume_after: after,
      path_prefix: prefix,
      resume_relative_path: path
    }
  end

  # INIT-020/SPEC-007 — last admitted pack as a library-relative path only.
  def safe_last_pack_path
    safe_pack_path(resume_after)
  end

  def safe_pack_path(value)
    path = value.to_s
    return nil if path.blank? || path.include?("\0")
    return nil if path.start_with?("/", "\\") || path.match?(ABSOLUTE_DRIVE)

    parts = path.tr("\\", "/").split("/").reject(&:blank?)
    return nil if parts.empty? || parts.size > 2
    return nil unless parts.all? { |part| safe_pack_segment?(part) }

    parts.join("/")
  end

  def safe_relative_path(value)
    path = value.to_s
    return nil if path.blank? || path.include?("\0")
    return nil if path.start_with?("/", "\\") || path.match?(ABSOLUTE_DRIVE)

    parts = path.tr("\\", "/").split("/").reject(&:blank?)
    return nil if parts.empty? || parts.any? { |part| part == "." || part == ".." }

    parts.join("/")
  end

  private

  ABSOLUTE_DRIVE = /\A[A-Za-z]:[\\\/]/.freeze

  def safe_pack_segment?(part)
    part.present? && part != "." && part != ".." && !part.include?("\0") && !part.start_with?(".")
  end

  def resume_cursor
    return unless resume_after.present? || budget_exhausted?

    if library.association(:scan_cursors).loaded?
      if resume_after.present?
        library.scan_cursors.find { |cursor| cursor.path_prefix == resume_after }
      else
        library.scan_cursors.find { |cursor| cursor.resume_relative_path.present? }
      end
    elsif resume_after.present?
      library.scan_cursors.find_by(path_prefix: resume_after)
    else
      library.scan_cursors.where.not(resume_relative_path: [nil, ""]).first
    end
  end
end
