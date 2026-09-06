# frozen_string_literal: true

# Deterministic proposals from a catalog snapshot or first-level folders.
# Keep sidecar_ref values stable so 3dvibe can upsert on poll.
module CuratorStub
  module_function

  def proposals_for(models)
    list = Array(models).map { |model| stringify(model) }.sort_by { |model| [model["folder_name"].to_s, model["id"].to_i] }
    return [] if list.empty?

    first, second = list[0], list[1]
    drafts = []
    drafts << tag_draft(first)
    drafts << rename_draft(rename_target(list))
    drafts << move_draft(second) if second
    drafts << merge_draft(first, second) if second
    drafts << organize_draft(list.first(3))
    drafts.compact
  end

  def models_from_library_root(root)
    return [] if root.to_s.empty? || !Dir.exist?(root)

    Dir.children(root).sort.filter_map do |name|
      next if name.start_with?(".")
      next unless File.directory?(File.join(root, name))

      { "id" => nil, "folder_name" => name, "title" => humanize(name), "tags" => [] }
    end
  end

  def tag_draft(model)
    tag = model["folder_name"].to_s.split(/[-_]/).first.to_s.downcase
    tag = "fixture" if tag.empty?
    draft(
      "tag",
      "stub:tag:#{model['folder_name']}",
      "Tag #{model['title'] || model['folder_name']} as #{tag}",
      "model_id" => model["id"],
      "folder_name" => model["folder_name"],
      "tag" => tag,
      "tags" => [tag]
    )
  end

  def rename_draft(model)
    return if model.nil? || model["folder_name"].to_s.end_with?("-curated")

    to = "#{model['folder_name']}-curated"
    draft(
      "rename",
      "stub:rename:#{model['folder_name']}",
      "Rename #{model['folder_name']} → #{to}",
      "model_id" => model["id"],
      "folder_name" => model["folder_name"],
      "to" => to,
      "title" => humanize(to)
    )
  end

  def move_draft(model)
    return if model["folder_name"].to_s.end_with?("-shelf")

    to = "#{model['folder_name']}-shelf"
    draft(
      "move",
      "stub:move:#{model['folder_name']}",
      "Move #{model['folder_name']} → #{to}",
      "model_id" => model["id"],
      "from" => model["folder_name"],
      "to" => to
    )
  end

  def merge_draft(source, target)
    draft(
      "merge",
      "stub:merge:#{source['folder_name']}:#{target['folder_name']}",
      "Merge #{source['folder_name']} into #{target['folder_name']}",
      "source_id" => source["id"],
      "target_id" => target["id"],
      "left_id" => source["id"],
      "right_id" => target["id"],
      "from" => source["folder_name"],
      "to" => target["folder_name"]
    )
  end

  def organize_draft(models)
    names = models.map { |model| model["folder_name"] }
    ids = models.map { |model| model["id"] }
    draft(
      "organize",
      "stub:organize:fixture",
      "Tag a fixture shelf across #{names.join(', ')}",
      "shelf" => "fixture",
      "folder_names" => names,
      "model_ids" => ids,
      "tag" => "fixture"
    )
  end

  def rename_target(models)
    models.find { |model| !model["folder_name"].to_s.end_with?("-curated") } || models.first
  end

  def draft(kind, ref, summary, payload)
    { "kind" => kind, "sidecar_ref" => ref, "summary" => summary, "payload" => payload }
  end

  def stringify(model)
    model.respond_to?(:stringify_keys) ? model.stringify_keys : model.transform_keys(&:to_s)
  end

  def humanize(folder_name)
    folder_name.to_s.tr("_-", " ").squeeze(" ").strip.split.map(&:capitalize).join(" ")
  end
end
