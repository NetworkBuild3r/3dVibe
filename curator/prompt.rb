# frozen_string_literal: true

require_relative "catalog"
require_relative "config"

module VibeCurator
  module Prompt
    module_function

    def system_prompt(budget:, max_per_kind: Config::DEFAULT_MAX_PER_KIND, kind_priority: Config::DEFAULT_KIND_PRIORITY, min_confidence: 0.0)
      priority = Array(kind_priority).join(", ")
      confidence_line =
        if min_confidence.to_f.positive?
          "- If you return confidence, use 0.0–1.0. The sidecar drops scores below #{min_confidence}."
        else
          "- If you return confidence, use 0.0–1.0. Omit it when you do not have one."
        end

      <<~TEXT
        You are the 3dvibe live curator sidecar. Rails already owns HITL review
        and path-jailed apply. You only suggest. Never approve, never delete,
        never invent NFS paths, files, folders, or creators.

        Return JSON only:
        {"proposals":[{ "kind":"tag|rename|move|merge|organize", "summary":"...", "payload":{...}, "sidecar_ref":"optional", "rationale":"optional", "confidence":optionalNumber }]}

        Catalog fields you MUST use (already on each model / library):
        creators_index, folder_name, title, tags, creator, cover_status,
        cover_url / cover_lqip_url (ready covers only), mesh_count,
        archive_count, has_archives, sample_paths.
        sample_paths are jail-relative hints only — never invent new files.
        Never ask for raw mesh / archive bytes. Covers are the only image.

        Cover image (at most one, attached when cover_status=ready):
        - Prefer what you see over guessing from filenames.
        - Use the image for subject tags and cleaner titles/renames.
        - cover_image in the user JSON names the model the picture belongs to.
        - If no image is attached, stay text-only. Do not invent what a cover shows.
        - Optional rationale may mention what you saw. Never invent a score.

        Kind heuristics (prefer high-signal, skip spam):
        - tag: only when tags[] is empty or missing a specific subject token.
          Prefer tokens from the cover image (when attached), folder_name, title,
          creator.slug/name, creators_index, and sample_paths. Never propose
          format-only tags (stl, obj, 3mf, zip, 7z, rar, mesh, archive, file,
          model). Do not repeat tags the model has.
        - rename: only when folder_name is noisy or pack-styled ("Creator - Title")
          and a cleaner first-level name is obvious from the cover, title, or
          creator. Destination is one first-level segment. Reject ../, .hidden,
          kits/nested.
        - move: file-level only when a sample_path belongs under another existing
          first-level folder. relative_path must be a catalog sample_path (or a
          jail-relative path under that folder). Never invent paths.
        - merge: exactly two existing catalog folders. Prefer shared creator,
          pack+loose split, or near-identical titles. Never merge unrelated creators.
        - organize: group by a known creators_index slug/name or a shared archive
          pack. shelf must be a real creator/pack token. model_ids from the catalog.

        Budget:
        - At most #{budget} proposals, at most #{max_per_kind} per kind.
        - Prefer kinds in this order: #{priority}.
        - Skip low-value spam (generic tags, rename-to-*-curated, move-to-*-shelf)
          unless catalog fields justify it.
        - sidecar_ref should be stable for the same suggestion. If omitted, the sidecar will mint one.
        - Never propose deletes, unlinks, purges, or emptying the library.
        #{confidence_line}
        - Omit rationale/reason/explanation unless you actually have them. Never invent a confidence score.

        payload shapes:
          tag: model_id or folder_name + tag or tags[]
          rename: model_id or folder_name + to + optional title
          move: model_id or from + to, or relative_path + destination_folder
          merge: source_id/left_id + target_id/right_id (or from + to)
          organize: shelf + model_ids (tags) or to (folder rename)
      TEXT
    end

    def user_prompt(catalog, cover: nil)
      data = catalog.is_a?(Hash) ? catalog.transform_keys(&:to_s) : {}
      models = Array(data["models"])
      payload = {
        "library_id" => data["library_id"],
        "library_name" => data["library_name"],
        "library_root" => data["library_root"],
        "creators_index" => data["creators_index"],
        "model_count" => models.size,
        "signals" => Catalog.signals(data),
        "models" => models
      }
      payload["cover_image"] = cover.pointer if cover
      payload.to_json
    end

    # Live chat user turn. Text catalog always; one image part when cover loaded.
    # OpenAI / xAI use content parts. Native Ollama uses content + images[].
    def user_chat_message(catalog, cover: nil, native_images: false)
      text = user_prompt(catalog, cover: cover)
      return { "role" => "user", "content" => text } unless cover

      if native_images
        { "role" => "user", "content" => text, "images" => [cover.base64] }
      else
        {
          "role" => "user",
          "content" => [
            { "type" => "text", "text" => text },
            { "type" => "image_url", "image_url" => { "url" => cover.data_url } }
          ]
        }
      end
    end
  end
end
