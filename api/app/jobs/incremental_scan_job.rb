class IncrementalScanJob < ApplicationJob
  queue_as :scan

  def perform(library_id, path_prefix = nil, uploaded_by_id = nil, trigger = nil)
    library = Library.find(library_id)
    uploaded_by = User.find_by(id: uploaded_by_id) if uploaded_by_id
    prefix = path_prefix.to_s.presence
    kind = trigger.presence || inferred_trigger(prefix)

    run = ScanRun.claim!(library, path_prefix: prefix, trigger: kind, user: uploaded_by)
    return unless run

    result = LibraryScanner.new(
      library,
      uploaded_by: uploaded_by,
      budget: ScanBudget.from_env,
      trigger: kind
    ).scan!(path_prefix: prefix, run: run)

    return unless result.budgeted? && prefix.blank?

    IncrementalScanJob.perform_later(library_id, nil, uploaded_by_id, kind)
  end

  private

  def inferred_trigger(prefix)
    prefix.present? ? ScanRun::TRIGGER_TARGETED : ScanRun::TRIGGER_JOB
  end
end
