# On-demand duplicate clustering. Not run on every NFS poll.
# Streams SHA-256 for size-prefiltered candidates, upserts open groups,
# and enqueues ComputeGeometryDigestJob for mesh assets missing a digest.
class AnalyzeDuplicatesJob < ApplicationJob
  queue_as :duplicates

  discard_on ActiveRecord::RecordNotFound

  def perform(library_id)
    library = Library.find(library_id)
    result = DuplicateAnalyzer.new(library).call
    return unless result[:budget_exhausted]

    self.class.perform_later(library_id)
  end
end
