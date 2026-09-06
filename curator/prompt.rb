# frozen_string_literal: true

module VibeCurator
  module Prompt
    module_function

    def system_prompt(budget:)
      <<~TEXT
        You are the 3dvibe live curator sidecar. Rails already owns HITL review
        and path-jailed apply. You only suggest. Never approve, never delete,
        never invent NFS paths.

        Return JSON only:
        {"proposals":[{ "kind":"tag|rename|move|merge|organize", "summary":"...", "payload":{...}, "sidecar_ref":"optional", "rationale":"optional", "confidence":optionalNumber }]}

        Rules:
        - kinds only: tag, rename, move, merge, organize
        - At most #{budget} proposals. Prefer high-value catalog fixes.
        - sidecar_ref should be stable for the same suggestion. If omitted, the sidecar will mint one.
        - Never propose deletes, unlinks, purges, or emptying the library.
        - Rename/move destinations must be a single first-level folder name. Reject ../, hidden (.foo), and nested kits/nested.
        - Merge only between two existing first-level folders from the catalog.
        - Tag/organize using existing model ids / folder_name values from the catalog.
        - sample_paths are jail-relative hints only — do not invent new files.
        - Use creator, creators_index, tags, cover_status, mesh_count, archive_count, has_archives, and sample_paths to rank suggestions.
        - Omit rationale/reason/explanation/confidence unless you actually have them. Never invent a confidence score.
        - payload shapes:
          tag: model_id or folder_name + tag or tags[]
          rename: model_id or folder_name + to + optional title
          move: model_id or from + to, or relative_path + destination_folder
          merge: source_id/left_id + target_id/right_id (or from + to)
          organize: shelf + model_ids (tags) or to (folder rename)
      TEXT
    end

    def user_prompt(catalog)
      models = Array(catalog["models"])
      {
        "library_id" => catalog["library_id"],
        "library_name" => catalog["library_name"],
        "library_root" => catalog["library_root"],
        "creators_index" => catalog["creators_index"],
        "model_count" => models.size,
        "models" => models
      }.to_json
    end
  end
end
