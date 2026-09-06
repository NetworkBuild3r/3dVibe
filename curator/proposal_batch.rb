# frozen_string_literal: true

require "digest"
require_relative "config"
require_relative "path_jail"

module VibeCurator
  # Validates provider output against the HITL contract: allowed kinds,
  # stable sidecar_ref, path-jail, budget, optional pass-through fields.
  # Live providers also get catalog-grounded quality ranking so a poll does
  # not spam low-signal tags/renames. Stub keeps insertion order + budget only.
  module ProposalBatch
    PATH_KEYS = %w[to from folder_name destination_folder].freeze
    RELATIVE_KEYS = %w[relative_path destination_relative_path].freeze
    DELETE_KEYS = %w[delete unlink rm destroy purge remove].freeze
    PASS_THROUGH = %w[rationale reason explanation].freeze
    GENERIC_TAGS = %w[
      stl obj 3mf zip 7z rar gltf glb ply gcode
      file model mesh archive untitled unknown test fixture download print
    ].freeze
    KIND_WEIGHT = {
      "merge" => 50,
      "organize" => 40,
      "tag" => 30,
      "rename" => 15,
      "move" => 10
    }.freeze

    module_function

    def normalize(items, catalog:, provider:, budget:, env: ENV)
      jail = PathJail.new(catalog["library_root"])
      seen = {}
      sanitized = Array(items).filter_map do |item|
        proposal = sanitize(item, catalog: catalog, provider: provider, jail: jail)
        next unless proposal
        next if seen[proposal["sidecar_ref"]]

        seen[proposal["sidecar_ref"]] = true
        proposal
      end

      return sanitized.first(budget) if provider.to_s == "stub"

      select_quality(sanitized, catalog: catalog, budget: budget, env: env)
    end

    def sanitize(item, catalog:, provider:, jail:)
      data = item.is_a?(Hash) ? item.transform_keys(&:to_s) : {}
      kind = data["kind"].to_s.strip.downcase
      return if kind.empty? || !KINDS.include?(kind)
      return if delete_intent?(data)

      summary = data["summary"].to_s.strip
      return if summary.empty?

      payload = stringify_payload(data["payload"])
      return if delete_intent?(payload)
      return unless jail_payload!(payload, kind: kind, jail: jail)

      apply_pass_through!(data, payload)

      out = {
        "kind" => kind,
        "summary" => summary,
        "sidecar_ref" => stable_ref(provider, kind, payload, data["sidecar_ref"]),
        "payload" => payload
      }

      PASS_THROUGH.each do |key|
        value = data[key].to_s.strip
        value = payload[key].to_s.strip if value.empty?
        out[key] = value unless value.empty?
      end

      confidence = extract_confidence(data["confidence"])
      confidence ||= extract_confidence(payload["confidence"])
      if confidence
        out["confidence"] = confidence
        payload["confidence"] = confidence
      else
        payload.delete("confidence")
      end

      out
    end

    def select_quality(items, catalog:, budget:, env:)
      index = catalog_index(catalog)
      min_confidence = Config.min_confidence(env: env)
      max_per_kind = Config.max_per_kind(env: env)
      priority = Config.kind_priority(env: env)

      candidates = items.select { |item| grounded?(item, index) }
      candidates.reject! { |item| redundant?(item, index) }
      candidates.reject! { |item| low_signal?(item) }
      candidates.reject! { |item| low_confidence?(item, min_confidence) }

      ranked = candidates.sort_by do |item|
        [
          -score(item, index),
          priority_index(item["kind"], priority),
          item["summary"].to_s
        ]
      end

      counts = Hash.new(0)
      selected = []
      ranked.each do |item|
        break if selected.size >= budget

        kind = item["kind"]
        next if counts[kind] >= max_per_kind

        counts[kind] += 1
        selected << item
      end
      selected
    end

    def jail_payload!(payload, kind:, jail:)
      PATH_KEYS.each do |key|
        next unless payload.key?(key)
        return false if jail.looks_like_escape?(payload[key])

        if filesystem_dest?(kind, key)
          folder = jail.first_level(payload[key])
          return false unless folder

          payload[key] = folder
        elsif payload[key].to_s != ""
          folder = jail.first_level(payload[key])
          payload[key] = folder if folder
          return false if folder.nil? && %w[folder_name from].include?(key)
        end
      end

      RELATIVE_KEYS.each do |key|
        next unless payload.key?(key)
        return false if jail.looks_like_escape?(payload[key])

        rel = jail.jailed_relative(payload[key])
        return false unless rel

        payload[key] = rel
      end

      if payload["folder_names"].is_a?(Array)
        names = payload["folder_names"].map { |name| jail.first_level(name) }
        return false if names.any?(&:nil?)

        payload["folder_names"] = names
      end

      true
    end

    def filesystem_dest?(kind, key)
      return true if %w[to destination_folder].include?(key) && %w[rename move merge organize].include?(kind)
      return true if key == "from" && %w[move merge].include?(kind)

      false
    end

    def delete_intent?(data)
      return true if data["kind"].to_s.downcase.include?("delete")
      return true if DELETE_KEYS.include?(data["action"].to_s.downcase)

      DELETE_KEYS.any? { |key| data[key] == true || data[key].to_s.strip.downcase == "true" }
    end

    def stable_ref(provider, kind, payload, raw)
      if provider.to_s == "stub"
        cleaned = sanitize_ref(raw)
        return cleaned if cleaned
      end

      digest = Digest::SHA256.hexdigest(ref_key(kind, payload))[0, 16]
      "#{provider}:#{kind}:#{digest}"
    end

    def ref_key(kind, payload)
      parts =
        case kind
        when "tag"
          [payload["model_id"], payload["folder_name"], payload["tag"], Array(payload["tags"]).join(",")]
        when "rename", "move"
          [payload["model_id"], payload["folder_name"], payload["from"], payload["to"],
           payload["destination_folder"], payload["relative_path"]]
        when "merge"
          [payload["source_id"] || payload["left_id"], payload["target_id"] || payload["right_id"],
           payload["from"], payload["to"]]
        else
          [payload["shelf"], Array(payload["model_ids"]).join(","), payload["to"], payload["tag"]]
        end
      parts.map(&:to_s).join("|")
    end

    def sanitize_ref(value)
      cleaned = value.to_s.strip
      return if cleaned.empty?
      return unless cleaned.match?(/\A[A-Za-z0-9:._-]+\z/)
      return if cleaned.include?("..")

      cleaned[0, 120]
    end

    def stringify_payload(value)
      return {} unless value.is_a?(Hash)

      value.transform_keys(&:to_s)
    end

    def apply_pass_through!(data, payload)
      PASS_THROUGH.each do |key|
        value = data[key].to_s.strip
        next if value.empty?

        payload[key] = value if payload[key].to_s.strip.empty?
      end
    end

    # Accept 0.0–1.0 only. Out-of-range / non-numeric values are omitted (never invented).
    def extract_confidence(value)
      return if value.nil? || value == ""
      number = value.is_a?(Numeric) ? value.to_f : Float(value)
      return unless number.finite?
      return unless number >= 0.0 && number <= 1.0

      number
    rescue ArgumentError, TypeError
      nil
    end

    def catalog_index(catalog)
      models = Array(catalog["models"])
      by_id = {}
      by_folder = {}
      models.each do |model|
        data = model.is_a?(Hash) ? model.transform_keys(&:to_s) : {}
        by_id[data["id"].to_s] = data if data["id"]
        folder = data["folder_name"].to_s
        by_folder[folder.downcase] = data unless folder.empty?
      end
      creators = Array(catalog["creators_index"]).map { |row| row.is_a?(Hash) ? row.transform_keys(&:to_s) : {} }
      { by_id: by_id, by_folder: by_folder, creators: creators }
    end

    def grounded?(item, index)
      payload = item["payload"]
      case item["kind"]
      when "tag", "rename"
        !resolve_model(payload, index).nil?
      when "move"
        model = resolve_model(payload, index)
        return false unless model
        return true unless payload.key?("relative_path")

        path_known?(payload["relative_path"], model)
      when "merge"
        left = resolve_model(merge_side(payload, :source), index)
        right = resolve_model(merge_side(payload, :target), index)
        left && right && left != right
      when "organize"
        ids = Array(payload["model_ids"]).map(&:to_s).reject(&:empty?)
        names = Array(payload["folder_names"]).map(&:to_s)
        return true if ids.any? { |id| index[:by_id][id] }
        return true if names.any? { |name| index[:by_folder][name.downcase] }
        return true if payload["to"].to_s != "" && index[:by_folder][payload["to"].to_s.downcase]

        !resolve_model(payload, index).nil?
      else
        false
      end
    end

    def redundant?(item, index)
      payload = item["payload"]
      model = resolve_model(payload, index)
      case item["kind"]
      when "tag"
        tags = proposed_tags(payload)
        return true if tags.empty?
        return true if generic_only_tags?(tags)
        return true if model && tags.all? { |tag| existing_tags(model).include?(tag) }
      when "rename", "move"
        source = (payload["folder_name"] || payload["from"]).to_s
        dest = (payload["to"] || payload["destination_folder"]).to_s
        return true if dest != "" && dest.downcase == source.downcase
      when "merge"
        left = resolve_model(merge_side(payload, :source), index)
        right = resolve_model(merge_side(payload, :target), index)
        left && right && left == right
      else
        false
      end
    end

    def low_signal?(item)
      payload = item["payload"]
      case item["kind"]
      when "rename"
        dest = payload["to"].to_s
        folder = (payload["folder_name"] || payload["from"]).to_s
        dest.end_with?("-curated") && !pack_or_noisy_folder?(folder)
      when "move"
        dest = (payload["to"] || payload["destination_folder"]).to_s
        dest.end_with?("-shelf") && payload["relative_path"].to_s.empty?
      else
        false
      end
    end

    def low_confidence?(item, min_confidence)
      return false unless min_confidence.positive?
      return false unless item.key?("confidence")

      item["confidence"].to_f < min_confidence
    end

    def score(item, index)
      payload = item["payload"]
      model = resolve_model(payload, index)
      points = KIND_WEIGHT[item["kind"]] || 0
      points += (item["confidence"] * 10).round if item["confidence"]

      case item["kind"]
      when "tag"
        points += 8 if model && existing_tags(model).empty?
        points += 6 if creator_aligned?(payload, model, index)
        points += 4 if path_aligned?(payload, model)
        points -= 8 if generic_only_tags?(proposed_tags(payload))
      when "organize"
        points += 10 if creator_shelf?(payload, index)
        points += 6 if Array(payload["model_ids"]).size >= 2
        points += 4 if payload["shelf"].to_s != "" && !GENERIC_TAGS.include?(payload["shelf"].to_s.downcase)
      when "merge"
        left = resolve_model(merge_side(payload, :source), index)
        right = resolve_model(merge_side(payload, :target), index)
        points += 10 if left && right
        points += 8 if shared_creator?(left, right)
      when "rename"
        folder = (payload["folder_name"] || payload["from"]).to_s
        dest = payload["to"].to_s
        points += 8 if pack_or_noisy_folder?(folder)
        points -= 10 if dest.end_with?("-curated") && !pack_or_noisy_folder?(folder)
      when "move"
        points += 6 if model && path_known?(payload["relative_path"], model)
        dest = (payload["to"] || payload["destination_folder"]).to_s
        points -= 8 if dest.end_with?("-shelf") && payload["relative_path"].to_s.empty?
      end
      points
    end

    def resolve_model(payload, index, keys: %w[folder_name from])
      return unless payload.is_a?(Hash)

      if payload["model_id"]
        found = index[:by_id][payload["model_id"].to_s]
        return found if found
      end
      keys.each do |key|
        name = payload[key].to_s
        next if name.empty?

        found = index[:by_folder][name.downcase]
        return found if found
      end
      nil
    end

    def merge_side(payload, side)
      if side == :source
        { "model_id" => payload["source_id"] || payload["left_id"], "folder_name" => payload["from"] }
      else
        { "model_id" => payload["target_id"] || payload["right_id"], "folder_name" => payload["to"] }
      end
    end

    def proposed_tags(payload)
      tags = Array(payload["tags"]) + [payload["tag"]]
      tags.map { |tag| tag.to_s.strip.downcase }.reject(&:empty?).uniq
    end

    def existing_tags(model)
      Array(model && model["tags"]).map { |tag| tag.to_s.strip.downcase }.reject(&:empty?)
    end

    def generic_only_tags?(tags)
      list = tags.is_a?(Array) ? tags : proposed_tags("tag" => tags)
      list.any? && list.all? { |tag| GENERIC_TAGS.include?(tag) }
    end

    def creator_aligned?(payload, model, index)
      tokens = proposed_tags(payload)
      slugs = creator_tokens(model, index)
      tokens.any? { |tag| slugs.include?(tag) }
    end

    def path_aligned?(payload, model)
      return false unless model

      haystack = Array(model["sample_paths"]).join(" ").downcase
      proposed_tags(payload).any? { |tag| tag.size >= 3 && haystack.include?(tag) }
    end

    def path_known?(relative_path, model)
      path = relative_path.to_s.tr("\\", "/").sub(%r{\A/+}, "")
      return false if path.empty?

      samples = Array(model["sample_paths"]).map { |item| item.to_s.tr("\\", "/") }
      return true if samples.include?(path)

      folder = model["folder_name"].to_s
      return true if folder != "" && (path == folder || path.start_with?("#{folder}/"))
      return true if samples.any? { |sample| File.basename(sample) == File.basename(path) }

      false
    end

    def creator_shelf?(payload, index)
      shelf = payload["shelf"].to_s.strip.downcase
      return false if shelf.empty?

      creator_tokens(nil, index).include?(shelf)
    end

    def creator_tokens(model, index)
      tokens = []
      if model && model["creator"].is_a?(Hash)
        tokens << model["creator"]["slug"].to_s
        tokens << model["creator"]["name"].to_s
      end
      Array(index[:creators]).each do |row|
        tokens << row["slug"].to_s
        tokens << row["name"].to_s
      end
      tokens.map { |token| token.strip.downcase }.reject(&:empty?).uniq
    end

    def shared_creator?(left, right)
      return false unless left && right
      return false unless left["creator"].is_a?(Hash) && right["creator"].is_a?(Hash)

      left_id = left["creator"]["id"].to_s
      right_id = right["creator"]["id"].to_s
      return true if left_id != "" && left_id == right_id

      left["creator"]["slug"].to_s.downcase == right["creator"]["slug"].to_s.downcase &&
        left["creator"]["slug"].to_s != ""
    end

    def pack_or_noisy_folder?(name)
      value = name.to_s
      value.match?(/\s+-\s+/) || value.match?(/\A(untitled|download|copy|dump)/i)
    end

    def priority_index(kind, priority)
      idx = priority.index(kind)
      idx.nil? ? priority.size : idx
    end
  end
end
