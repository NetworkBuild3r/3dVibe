# Deterministic fake proposals from the current catalog.
# Used when VIBE_CURATOR_URL=stub so HITL works without Spark/DGX.
class CurationStubProposals
  def initialize(library, models: nil)
    @library = library
    @models = Array(models || library.vibe_models.includes(:tags).order(:folder_name, :id))
  end

  def drafts
    return [] if @models.empty?

    [
      tag_draft(@models.first),
      rename_draft(rename_target),
      move_draft,
      merge_draft,
      organize_draft
    ].compact
  end

  private

  def tag_draft(model)
    tag = stub_tag_for(model.folder_name)
    draft(
      kind: "tag",
      ref: "stub:tag:#{model.folder_name}",
      summary: "Tag #{model.title} as #{tag}",
      payload: { "model_id" => model.id, "folder_name" => model.folder_name, "tag" => tag, "tags" => [tag] }
    )
  end

  def rename_draft(model)
    return if model.blank? || model.folder_name.end_with?("-curated")

    to = "#{model.folder_name}-curated"
    draft(
      kind: "rename",
      ref: "stub:rename:#{model.folder_name}",
      summary: "Rename #{model.folder_name} → #{to}",
      payload: {
        "model_id" => model.id,
        "folder_name" => model.folder_name,
        "to" => to,
        "title" => CurationApplier.humanize(to)
      }
    )
  end

  def move_draft
    return if @models.size < 2

    model = @models[1]
    to = "#{model.folder_name}-shelf"
    return if model.folder_name.end_with?("-shelf")

    draft(
      kind: "move",
      ref: "stub:move:#{model.folder_name}",
      summary: "Move #{model.folder_name} → #{to}",
      payload: { "model_id" => model.id, "from" => model.folder_name, "to" => to }
    )
  end

  def merge_draft
    return if @models.size < 2

    source, target = @models.first(2)
    draft(
      kind: "merge",
      ref: "stub:merge:#{source.folder_name}:#{target.folder_name}",
      summary: "Merge #{source.folder_name} into #{target.folder_name}",
      payload: {
        "source_id" => source.id,
        "target_id" => target.id,
        "left_id" => source.id,
        "right_id" => target.id,
        "from" => source.folder_name,
        "to" => target.folder_name
      }
    )
  end

  def organize_draft
    names = @models.first(3).map(&:folder_name)
    ids = @models.first(3).map(&:id)
    draft(
      kind: "organize",
      ref: "stub:organize:fixture",
      summary: "Tag a fixture shelf across #{names.join(', ')}",
      payload: { "shelf" => "fixture", "folder_names" => names, "model_ids" => ids, "tag" => "fixture" }
    )
  end

  def rename_target
    @models.find { |model| !model.folder_name.end_with?("-curated") } || @models.first
  end

  def stub_tag_for(folder_name)
    head = folder_name.to_s.split(/[-_]/).first.to_s.downcase
    head.present? ? head : "fixture"
  end

  def draft(kind:, ref:, summary:, payload:)
    CurationSidecar::ProposalDraft.new(kind: kind, summary: summary, payload: payload, sidecar_ref: ref)
  end
end
