# frozen_string_literal: true

require_relative "config"
require_relative "path_jail"
require_relative "stub_proposals"

module VibeCurator
  # Normalizes the Rails #20 catalog snapshot (or a GET fallback listing).
  module Catalog
    COVER_STATUSES = %w[missing pending ready failed].freeze
    MESH_EXT = %w[.stl .obj .3mf .gltf .glb .ply].freeze
    ARCHIVE_EXT = %w[.zip .7z .rar .3mf].freeze

    module_function

    def normalize(payload, query: {}, env: ENV)
      data = stringify(payload)
      query = stringify(query)
      root = data["library_root"].to_s
      root = query["library_root"].to_s if root.empty?
      root = Config.library_root(env: env) if root.empty?

      hint = data["provider_hint"].to_s
      hint = query["provider_hint"].to_s if hint.empty?
      hint = Config.normalize_provider(hint)

      models = Array(data["models"]).map { |model| normalize_model(model, root) }
      models = models_from_root(root) if models.empty?

      normalized = {
        "library_id" => data["library_id"],
        "library_name" => data["library_name"].to_s,
        "library_root" => root,
        "provider_hint" => hint,
        "creators_index" => normalize_creators(data["creators_index"]),
        "models" => models
      }
      # POST body only. Never copy curator_runtime from the query string.
      runtime = data["curator_runtime"]
      normalized["curator_runtime"] = stringify(runtime) if runtime.is_a?(Hash)
      normalized
    end

    def rank_for_inference(models, limit:)
      Array(models).sort_by { |model| [rank_score(model), model["folder_name"].to_s, model["id"].to_i] }
        .first(limit)
    end

    # Compact briefing for the live prompt. Caps keep the user message small.
    def signals(catalog, cap: 12)
      models = Array(catalog.is_a?(Hash) ? catalog["models"] : nil)
      creators = Array(catalog.is_a?(Hash) ? catalog["creators_index"] : nil)
      {
        "untagged" => take_briefs(models.select { |model| Array(model["tags"]).empty? }, cap),
        "missing_creator" => take_briefs(models.select { |model| model["creator"].nil? }, cap),
        "archive_packs" => take_briefs(models.select { |model| model["has_archives"] }, cap),
        "pack_style_folders" => take_briefs(models.select { |model| pack_style_folder?(model["folder_name"]) }, cap),
        "known_creators" => creators.filter_map { |row| row["slug"].to_s.strip.empty? ? row["name"].to_s : row["slug"].to_s }.first(50)
      }
    end

    def models_from_root(root)
      CuratorStub.models_from_library_root(root).map { |model| enrich_from_disk(model, root) }
    end

    def normalize_model(model, root)
      data = stringify(model)
      folder = data["folder_name"].to_s
      sample = Array(data["sample_paths"]).map { |path| jail_hint(path, root) }.compact.first(5)
      archive_count = int_or_nil(data["archive_count"])
      status = normalize_cover(data["cover_status"])
      row = {
        "id" => data["id"],
        "folder_name" => folder,
        "title" => data["title"].to_s,
        "tags" => Array(data["tags"]).map { |tag| tag.to_s.strip }.reject(&:empty?),
        "asset_count" => int_or_nil(data["asset_count"]),
        "byte_size" => int_or_nil(data["byte_size"]),
        "creator" => normalize_creator(data["creator"]),
        "cover_status" => status,
        "mesh_count" => int_or_nil(data["mesh_count"]),
        "archive_count" => archive_count,
        "has_archives" => truthy?(data["has_archives"]) || archive_count.to_i.positive?,
        "sample_paths" => sample
      }
      # Ready covers only — same card URLs Rails #42 sends. Live vision
      # prefers LQIP, else cover. Missing/pending/failed stay text-only.
      if status == "ready"
        url = normalize_cover_url(data["cover_url"])
        lqip = normalize_cover_url(data["cover_lqip_url"])
        row["cover_url"] = url if url
        row["cover_lqip_url"] = lqip if lqip
      end
      row
    end

    def enrich_from_disk(model, root)
      folder = model["folder_name"].to_s
      dir = File.join(root, folder)
      samples = []
      mesh_count = 0
      archive_count = 0
      if File.directory?(dir)
        Dir.children(dir).sort.each do |name|
          next if name.start_with?(".")

          path = File.join(dir, name)
          next unless File.file?(path)

          ext = File.extname(name).downcase
          mesh_count += 1 if MESH_EXT.include?(ext)
          archive_count += 1 if ARCHIVE_EXT.include?(ext)
          samples << "#{folder}/#{name}" if samples.size < 5
        end
      end
      model.merge(
        "asset_count" => samples.size,
        "mesh_count" => mesh_count,
        "archive_count" => archive_count,
        "has_archives" => archive_count.positive?,
        "sample_paths" => samples
      )
    end

    def normalize_creators(list)
      Array(list).filter_map do |row|
        data = stringify(row)
        name = data["name"].to_s
        next if name.empty?

        {
          "id" => data["id"],
          "slug" => data["slug"].to_s,
          "name" => name,
          "model_count" => int_or_nil(data["model_count"])
        }
      end.first(50)
    end

    def normalize_creator(value)
      return if value.nil? || value == ""
      return unless value.is_a?(Hash)

      data = stringify(value)
      return if data["name"].to_s.empty? && data["slug"].to_s.empty?

      { "id" => data["id"], "slug" => data["slug"].to_s, "name" => data["name"].to_s }
    end

    def normalize_cover(value)
      name = value.to_s.strip.downcase
      COVER_STATUSES.include?(name) ? name : nil
    end

    # Card URLs only. Reject NFS / mesh paths so vision cannot slurp a raw file.
    def normalize_cover_url(value)
      text = value.to_s.strip
      return if text.empty?
      return text if text.start_with?("data:image/")
      return text if text.match?(/\Ahttps?:\/\//i)
      return text if text.match?(%r{\A/covers/[0-9]+(?:\.lqip)?\.webp\z})

      nil
    end

    def jail_hint(path, root)
      PathJail.new(root).jailed_relative(path)
    end

    def rank_score(model)
      score = 0
      tags = Array(model["tags"])
      folder = model["folder_name"].to_s
      score -= 4 if tags.empty?
      score -= 2 if model["cover_status"].to_s.empty? || %w[missing failed].include?(model["cover_status"].to_s)
      if model["creator"].nil?
        score -= pack_style_folder?(folder) ? 3 : 1
      end
      score -= 2 if model["has_archives"]
      score -= 1 if model["mesh_count"].to_i >= 3
      score -= 1 if noisy_folder?(folder)
      score
    end

    def pack_style_folder?(name)
      value = name.to_s
      return true if value.match?(/\s+-\s+/)
      return true if value.match?(/\A[A-Za-z0-9]+(?:_[A-Za-z0-9]+){2,}\z/) && value.include?("_")

      false
    end

    def noisy_folder?(name)
      value = name.to_s.downcase
      return true if value.match?(/\A(untitled|download|new folder|copy|dump)([-_ ]|$)/)
      return true if value.match?(/\(\d+\)\z/)

      false
    end

    def take_briefs(models, cap)
      Array(models).first(cap).map { |model| model_brief(model) }
    end

    def model_brief(model)
      creator = model["creator"]
      {
        "id" => model["id"],
        "folder_name" => model["folder_name"],
        "title" => model["title"],
        "creator" => creator.is_a?(Hash) ? (creator["slug"].to_s.empty? ? creator["name"] : creator["slug"]) : nil,
        "tags" => Array(model["tags"]),
        "cover_status" => model["cover_status"],
        "has_archives" => model["has_archives"],
        "mesh_count" => model["mesh_count"],
        "archive_count" => model["archive_count"],
        "sample_paths" => Array(model["sample_paths"])
      }
    end

    def stringify(value)
      return {} unless value.is_a?(Hash)

      value.respond_to?(:transform_keys) ? value.transform_keys(&:to_s) : value
    end

    def int_or_nil(value)
      return if value.nil? || value == ""

      Integer(value)
    rescue ArgumentError, TypeError
      nil
    end

    def truthy?(value)
      value == true || %w[1 true yes on].include?(value.to_s.strip.downcase)
    end
  end
end
