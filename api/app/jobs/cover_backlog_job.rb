# Drains pending covers and ready-without-LQIP in paced batches.
# LQIP backfill does not flip ready → pending or failed (CoverGenerator
# writes from the existing webp). Scan still marks pending; this job is
# the steady-state GenerateCoverJob pump once CoverPacer defers overflow.
class CoverBacklogJob < ApplicationJob
  queue_as :covers

  def perform
    CoverPacer.drain!
  end

  def self.ensure_scheduled!
    return if CoverPacer.backlog_job_queued?

    delay = CoverPacer.pace_seconds
    if delay.positive?
      set(wait: delay).perform_later
    else
      perform_later
    end
  end
end
