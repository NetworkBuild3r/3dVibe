# Interface for an external HITL curation sidecar.
# The sidecar is not required at runtime. It may POST proposals into the API
# or be polled later. This object only documents the expected payload shape.
class CurationSidecar
  ProposalDraft = Struct.new(:kind, :summary, :payload, :sidecar_ref, keyword_init: true)

  def initialize(library, endpoint: ENV["CURATION_SIDECAR_URL"])
    @library = library
    @endpoint = endpoint
  end

  def fetch_drafts
    return [] if @endpoint.blank?

    # Intentionally a no-op in MVP. Keep Spark / any GPU sidecar offline.
    []
  end

  def ingest!(drafts)
    drafts.map do |draft|
      @library.curation_proposals.create!(
        kind: draft.kind,
        summary: draft.summary,
        payload: draft.payload || {},
        sidecar_ref: draft.sidecar_ref,
        status: CurationProposal::PENDING
      )
    end
  end
end
