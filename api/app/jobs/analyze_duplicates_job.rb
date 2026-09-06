# On-demand duplicate clustering. Not run on every NFS poll.
# Fingerprints pending stl/obj/3mf meshes, streams SHA-256 for size-prefiltered
# candidates, upserts open groups, and enqueues leftover geometry jobs.
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
