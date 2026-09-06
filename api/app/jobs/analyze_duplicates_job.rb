# On-demand duplicate clustering. Not run on every NFS poll.
# Fingerprints pending loose stl/obj/3mf meshes, streams SHA-256 for
# size-prefiltered candidates, upserts open groups (including archive
# members that share a geometry_digest), and enqueues leftover geometry
# jobs. Archive-member fingerprints are a Rendering stub — never extract.
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
