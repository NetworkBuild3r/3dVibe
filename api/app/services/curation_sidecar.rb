# Interface for an external HITL curation sidecar.
#
# Contract (HTTP):
#   POST {VIBE_CURATOR_URL}/proposals
#   GET  {VIBE_CURATOR_URL}/proposals?library_id=&library_root=
#   Authorization: Bearer {VIBE_CURATOR_TOKEN}
#   X-Curator-Token: {VIBE_CURATOR_TOKEN}
#
# Env:
#   VIBE_CURATOR_URL        base URL, or `stub` for in-process fixtures
#   VIBE_CURATOR_TOKEN      shared bearer token (optional in stub mode)
#   VIBE_CURATOR_TIMEOUT    seconds (default 8)
#   VIBE_CURATOR_STUB       when `1`/`true`, use in-process stub if URL is blank
#   VIBE_CURATOR_PROVIDER   optional hint (ollama|xai|stub|…) sent as catalog
#                           `provider_hint`. Does not replace VIBE_CURATOR_URL.
#   Owner UI CuratorSetting overrides provider / Ollama URL+model / xAI key
#   when set. POST /proposals also gets request-scoped `curator_runtime`.
#
# Live providers must return a stable `sidecar_ref` per suggestion so upsert
# is idempotent. Pending rows update; reviewed rows are never clobbered.
# Rails only polls + HITL apply. Inference adapters live in Rendering.
class CurationSidecar
  ProposalDraft = Struct.new(:kind, :summary, :payload, :sidecar_ref, keyword_init: true)
  FetchResult = Struct.new(:drafts, :provider, keyword_init: true)
  SAMPLE_PATH_LIMIT = 5
  CREATORS_INDEX_LIMIT = 50
  OPTIONAL_HINT_KEYS = %w[rationale reason explanation confidence].freeze

  def self.payload_with_hints(data)
    source = data.respond_to?(:to_unsafe_h) ? data.to_unsafe_h : data
    source = (source.presence || {}).stringify_keys
    payload = (source["payload"].presence || {}).to_h.stringify_keys
    OPTIONAL_HINT_KEYS.each do |key|
      next unless source.key?(key)
      next if !payload[key].nil? && payload[key] != ""
      value = source[key]
      next if value.nil? || value == ""
      payload[key] = value
    end
    payload
  end

  def initialize(library, endpoint: ENV["VIBE_CURATOR_URL"], token: ENV["VIBE_CURATOR_TOKEN"],
                 provider_hint: nil, client: nil)
    @library = library
    @endpoint = endpoint.to_s.strip
    @token = token
    @provider_hint = provider_hint.nil? ? CuratorRuntime.provider : provider_hint.to_s.strip.presence
    @client = client
  end

  def stub_mode?
    value = @endpoint.downcase
    return true if %w[stub stub://local internal].include?(value)
    return true if @endpoint.blank? && truthy?(ENV["VIBE_CURATOR_STUB"])
    return true if @endpoint.blank? && !Rails.env.production?

    false
  end

  def catalog
    models = @library.vibe_models.includes(:tags, :creator, :assets).order(:folder_name, :id)
    {
      library_id: @library.id,
      library_name: @library.name,
      library_root: @library.root_path,
      provider_hint: @provider_hint,
      curator_runtime: CuratorRuntime.for_sidecar,
      creators_index: creators_index,
      models: models.map { |model| catalog_model(model) }
    }
  end

  def fetch_drafts
    fetch_result.drafts
  end

  def ingest_remote!
    result = fetch_result
    records = ingest!(result.drafts)
    record_poll_success!(result.provider)
    records
  rescue CurationHttpClient::Error => e
    record_poll_error!(e)
    raise
  end

  def ingest!(drafts)
    Array(drafts).filter_map { |draft| upsert_draft!(draft) }
  end

  private

  def fetch_result
    if stub_mode?
      return FetchResult.new(drafts: CurationStubProposals.new(@library).drafts, provider: resolved_provider)
    end
    return FetchResult.new(drafts: [], provider: resolved_provider) if @endpoint.blank?

    remote = (@client || CurationHttpClient.new(endpoint: @endpoint, token: @token)).fetch_proposals(catalog)
    return remote if remote.is_a?(FetchResult)

    FetchResult.new(drafts: Array(remote), provider: resolved_provider)
  end

  def catalog_model(model)
    assets = model.assets.sort_by { |asset| [asset.relative_path.to_s, asset.id] }
    mesh_count = assets.count(&:mesh?)
    archive_count = assets.count(&:archive?)
    row = {
      id: model.id,
      folder_name: model.folder_name,
      title: model.title,
      tags: model.tags.map(&:name),
      asset_count: model.asset_count,
      byte_size: model.byte_size,
      creator: model.creator&.as_card,
      cover_status: model.cover_status,
      mesh_count: mesh_count,
      archive_count: archive_count,
      has_archives: archive_count.positive?,
      sample_paths: assets.first(SAMPLE_PATH_LIMIT).map { |asset| jail_relative_path(model, asset) }
    }
    # Ready covers only: same card URLs. Sidecar prefers LQIP, else cover_url.
    # Missing/pending/failed stay text-only (omit image keys even if leftovers exist).
    if model.cover_status == VibeModel::COVER_READY
      url = model.cover_url.to_s.presence
      lqip = model.cover_lqip_url.to_s.presence
      row[:cover_url] = url if url
      row[:cover_lqip_url] = lqip if lqip
    end
    row
  end

  def jail_relative_path(model, asset)
    File.join(model.folder_name, asset.relative_path.to_s).delete_prefix("/").tr("\\", "/")
  end

  def creators_index
    counts = @library.vibe_models.where.not(creator_id: nil).group(:creator_id).count
    return [] if counts.empty?

    Creator.where(id: counts.keys).ordered.sort_by { |creator| [-counts[creator.id].to_i, creator.name.to_s.downcase, creator.id] }
      .first(CREATORS_INDEX_LIMIT)
      .map do |creator|
        {
          id: creator.id,
          slug: creator.slug,
          name: creator.name,
          model_count: counts[creator.id].to_i
        }
      end
  end

  # Upsert by stable sidecar_ref. Live providers must reuse the same ref for
  # the same suggestion; reviewed rows are left untouched.
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

  def record_poll_success!(provider)
    @library.record_curation_poll!(provider: resolved_provider(provider), error: nil)
  end

  def record_poll_error!(error)
    @library.record_curation_poll!(
      provider: resolved_provider.presence || @library.last_provider,
      error: error.message
    )
  end

  def resolved_provider(remote = nil)
    remote.to_s.presence || @provider_hint || CuratorRuntime.provider
  end

  def truthy?(value)
    %w[1 true yes on].include?(value.to_s.strip.downcase)
  end
end
