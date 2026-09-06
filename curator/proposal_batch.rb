# frozen_string_literal: true

require "digest"
require_relative "config"
require_relative "path_jail"

module VibeCurator
  # Validates provider output against the HITL contract: allowed kinds,
  # stable sidecar_ref, path-jail, budget, optional pass-through fields.
  module ProposalBatch
    PATH_KEYS = %w[to from folder_name destination_folder].freeze
    RELATIVE_KEYS = %w[relative_path destination_relative_path].freeze
    DELETE_KEYS = %w[delete unlink rm destroy purge remove].freeze
    PASS_THROUGH = %w[rationale reason explanation].freeze

    module_function

    def normalize(items, catalog:, provider:, budget:)
      jail = PathJail.new(catalog["library_root"])
      seen = {}
      Array(items).filter_map do |item|
        proposal = sanitize(item, catalog: catalog, provider: provider, jail: jail)
        next unless proposal
        next if seen[proposal["sidecar_ref"]]

        seen[proposal["sidecar_ref"]] = true
        proposal
      end.first(budget)
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

      PASS_THROUGH.each do |key|
        value = data[key].to_s.strip
        next if value.empty?

        payload[key] = value if payload[key].to_s.strip.empty?
      end

      out = {
        "kind" => kind,
        "summary" => summary,
        "sidecar_ref" => stable_ref(provider, kind, payload, data["sidecar_ref"]),
        "payload" => payload
      }

      PASS_THROUGH.each do |key|
        value = data[key].to_s.strip
        out[key] = value unless value.empty?
      end

      confidence = extract_confidence(data["confidence"])
      if confidence
        out["confidence"] = confidence
        payload["confidence"] = confidence
      end

      out
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

    def extract_confidence(value)
      return if value.nil? || value == ""
      return value.to_f if value.is_a?(Numeric)

      Float(value)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
