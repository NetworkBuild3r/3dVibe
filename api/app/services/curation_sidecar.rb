# Interface for an external HITL curation sidecar.
#
# Contract (HTTP):
#   POST {VIBE_CURATOR_URL}/proposals
#   GET  {VIBE_CURATOR_URL}/proposals?library_id=&library_root=
#   Authorization: Bearer {VIBE_CURATOR_TOKEN}
#   X-Curator-Token: {VIBE_CURATOR_TOKEN}
#
# Env:
#   VIBE_CURATOR_URL       base URL, or `stub` for in-process fixtures
#   VIBE_CURATOR_TOKEN     shared bearer token (optional in stub mode)
#   VIBE_CURATOR_TIMEOUT   seconds (default 8)
#   VIBE_CURATOR_STUB      when `1`/`true`, use in-process stub if URL is blank
class CurationSidecar
  ProposalDraft = Struct.new(:kind, :summary, :payload, :sidecar_ref, keyword_init: true)

  def initialize(library, endpoint: ENV["VIBE_CURATOR_URL"], token: ENV["VIBE_CURATOR_TOKEN"])
    @library = library
    @endpoint = endpoint.to_s.strip
    @token = token
  end

  def stub_mode?
    value = @endpoint.downcase
    return true if %w[stub stub://local internal].include?(value)
    return true if @endpoint.blank? && truthy?(ENV["VIBE_CURATOR_STUB"])
    return true if @endpoint.blank? && !Rails.env.production?

    false
  end

  def catalog
    models = @library.vibe_models.includes(:tags).order(:folder_name, :id)
    {
      library_id: @library.id,
      library_name: @library.name,
      library_root: @library.root_path,
      models: models.map do |model|
        {
          id: model.id,
          folder_name: model.folder_name,
          title: model.title,
          tags: model.tags.map(&:name),
          asset_count: model.asset_count,
          byte_size: model.byte_size
        }
      end
    }
  end

  def fetch_drafts
    return CurationStubProposals.new(@library).drafts if stub_mode?
    return [] if @endpoint.blank?

    CurationHttpClient.new(endpoint: @endpoint, token: @token).fetch_proposals(catalog)
  end

  def ingest_remote!
    ingest!(fetch_drafts)
  end

  def ingest!(drafts)
    Array(drafts).filter_map { |draft| upsert_draft!(draft) }
  end

  private

  def upsert_draft!(draft)
    kind = draft.kind.to_s
    return unless CurationProposal::KINDS.include?(kind)
    return if draft.summary.blank?

    attrs = {
      kind: kind,
      summary: draft.summary.to_s,
      payload: (draft.payload.presence || {}).stringify_keys,
      sidecar_ref: draft.sidecar_ref.presence
    }

    if attrs[:sidecar_ref].present?
      record = @library.curation_proposals.find_or_initialize_by(sidecar_ref: attrs[:sidecar_ref])
      return record unless record.new_record? || record.pending?

      record.assign_attributes(attrs)
      record.status = CurationProposal::PENDING if record.new_record?
      record.save!
      record
    else
      @library.curation_proposals.create!(attrs.merge(status: CurationProposal::PENDING))
    end
  end

  def truthy?(value)
    %w[1 true yes on].include?(value.to_s.strip.downcase)
  end
end
