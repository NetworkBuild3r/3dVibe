# Drains pending covers in paced batches. Ready-without-LQIP is backfilled
# on the next CoverEnqueue (scan) so a failed tiny derivative cannot loop.
# Scan marks pending; this job is the only steady-state GenerateCoverJob
# pump once CoverPacer defers the rest of a NAS-scale enqueue storm.
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
