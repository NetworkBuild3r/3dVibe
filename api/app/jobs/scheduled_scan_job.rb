class ScheduledScanJob < ApplicationJob
  queue_as { ScanSettings.queue }

  def perform
    return unless ScanSettings.schedule_enabled?

    Library.find_each do |library|
      IncrementalScanJob.perform_later(library.id, nil, nil, ScanRun::TRIGGER_SCHEDULED)
    end
  end
end
