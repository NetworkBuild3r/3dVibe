# Budgeted cover generate. Payload is the locked CoverEnqueue JSON object.
# Writes back ready/failed via CoverWriteback.apply! (silent status, no toasts).
class GenerateCoverJob < ApplicationJob
  queue_as :covers

  discard_on ActiveRecord::RecordNotFound

  retry_on CoverGenerator::TransientError, attempts: 5, wait: :polynomially_longer do |job, error|
    job.fail_exhausted(error)
  end

  def perform(payload)
    CoverGenerator.call(payload)
  end

  def fail_exhausted(error)
    CoverGenerator.new(arguments.first).fail!(error)
  end
end
