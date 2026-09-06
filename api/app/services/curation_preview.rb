# Before/after view of a proposal for the HITL queue.
class CurationPreview
  def initialize(proposal)
    @proposal = proposal
    @library = proposal.library
  end

  def as_json
    {
      filesystem: @proposal.filesystem_change?,
      targets: targets.map { |model| card(model) },
      before: before_state,
      after: after_state
    }
  end

  private

  def payload
    @proposal.payload_hash
  end

  def targets
    ids = [
      payload["model_id"],
      payload["source_id"],
      payload["target_id"],
      payload["left_id"],
      payload["right_id"],
      *Array(payload["model_ids"])
    ].compact
    folders = [payload["folder_name"], payload["from"], payload["to"], *Array(payload["folder_names"])].compact
    found = []
    scope = @library.vibe_models.includes(:tags)
    found.concat(scope.where(id: ids).to_a) if ids.any?
    found.concat(scope.where(folder_name: folders).to_a) if folders.any?
    found.uniq
  end

  def primary
    targets.first
  end

  def before_state
    model = primary
    return {} unless model

    {
      model_id: model.id,
      title: model.title,
      folder_name: model.folder_name,
      tags: model.tags.map(&:name)
    }
  end

  def after_state
    case @proposal.kind
    when "tag", "organize"
      extra = [payload["tag"], payload["shelf"], *Array(payload["tags"])].flatten.compact.map { |n| n.to_s.downcase }
      {
        title: primary&.title,
        folder_name: @proposal.destination_folder.presence || primary&.folder_name,
        tags: ((primary&.tags&.map(&:name) || []) + extra).uniq
      }
    when "rename", "move"
      destination = @proposal.destination_folder.presence || payload["to"]
      {
        title: payload["title"].presence || CurationApplier.humanize(destination),
        folder_name: destination,
        tags: primary&.tags&.map(&:name) || []
      }
    when "merge"
      source = @library.vibe_models.find_by(id: payload["source_id"].presence || payload["left_id"])
      target = @library.vibe_models.find_by(id: payload["target_id"].presence || payload["right_id"]) ||
               @library.vibe_models.find_by(folder_name: payload["to"])
      {
        title: target&.title,
        folder_name: target&.folder_name || payload["to"],
        merge_from: source&.folder_name || payload["from"],
        tags: target&.tags&.map(&:name) || []
      }
    else
      {}
    end
  end

  def card(model)
    {
      id: model.id,
      title: model.title,
      folder_name: model.folder_name,
      tags: model.tags.map(&:name),
      asset_count: model.asset_count
    }
  end
end
