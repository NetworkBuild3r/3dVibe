# frozen_string_literal: true

require_relative "test_helper"

class PromptQualityTest < Minitest::Test
  include CuratorTestHelper

  def test_system_prompt_teaches_catalog_fields_and_budget
    text = VibeCurator::Prompt.system_prompt(
      budget: 8,
      max_per_kind: 3,
      kind_priority: %w[merge organize tag rename move],
      min_confidence: 0.4
    )
    assert_includes text, "creators_index"
    assert_includes text, "sample_paths"
    assert_includes text, "has_archives"
    assert_includes text, "folder_name"
    assert_includes text, "At most 8 proposals"
    assert_includes text, "at most 3 per kind"
    assert_includes text, "merge, organize, tag"
    assert_includes text, "below 0.4"
    assert_includes text, "Never invent"
    refute_includes text, "delete the library"
  end

  def test_user_prompt_includes_signals_and_catalog_fields
    json = JSON.parse(VibeCurator::Prompt.user_prompt(sample_catalog))
    assert_equal 1, json["library_id"]
    assert json["creators_index"].is_a?(Array)
    assert_equal "mz4250", json["creators_index"].first["slug"]
    assert json["signals"].is_a?(Hash)
    assert json["signals"]["untagged"].any? { |row| row["folder_name"] == "beta-two" }
    assert json["signals"]["missing_creator"].any? { |row| row["folder_name"] == "beta-two" }
    assert json["signals"]["archive_packs"].any? { |row| row["folder_name"] == "alpha-one" }
    assert_includes json["signals"]["known_creators"], "mz4250"
    alpha = json["models"].find { |row| row["folder_name"] == "alpha-one" }
    assert_equal ["alpha-one/horn.stl", "alpha-one/pack.zip"], alpha["sample_paths"]
    refute json.key?("curator_runtime")
  end

  def test_user_prompt_never_echoes_runtime_secrets
    catalog = sample_catalog.merge(
      "curator_runtime" => { "provider" => "xai", "xai_api_key" => "ui-secret-key" }
    )
    text = VibeCurator::Prompt.user_prompt(catalog)
    refute_includes text, "ui-secret-key"
    refute_includes text, "curator_runtime"
  end

  def test_rank_for_inference_prefers_untagged_and_archive_packs
    models = sample_catalog["models"] + [
      {
        "id" => 99,
        "folder_name" => "Mz4250 - Dragon",
        "title" => "Dragon",
        "tags" => [],
        "creator" => nil,
        "cover_status" => "missing",
        "mesh_count" => 4,
        "archive_count" => 1,
        "has_archives" => true,
        "sample_paths" => ["Mz4250 - Dragon/dragon.zip"]
      }
    ]
    ranked = VibeCurator::Catalog.rank_for_inference(models, limit: 2)
    assert_equal "Mz4250 - Dragon", ranked.first["folder_name"]
    assert_includes ranked.map { |row| row["folder_name"] }, "beta-two"
  end

  def test_ollama_prompt_body_includes_signals
    seen = nil
    transport = fake_ollama_transport(JSON.generate({
      "proposals" => [
        {
          "kind" => "tag",
          "summary" => "Tag Beta Two as mz4250",
          "payload" => { "model_id" => 13, "folder_name" => "beta-two", "tag" => "mz4250" }
        }
      ]
    })) do |_uri, request|
      seen = JSON.parse(request.body)
    end
    env = env_hash(
      "VIBE_CURATOR_PROVIDER" => "ollama",
      "VIBE_OLLAMA_URL" => "http://ollama.local:11434",
      "VIBE_CURATOR_MAX_PER_KIND" => "3",
      "VIBE_CURATOR_KIND_PRIORITY" => "merge,organize,tag"
    )
    VibeCurator::Service.proposals(payload: sample_catalog, env: env, transport: transport)
    system = seen["messages"][0]["content"]
    user = JSON.parse(seen["messages"][1]["content"])
    assert_includes system, "creators_index"
    assert_includes system, "at most 3 per kind"
    assert_includes system, "merge, organize, tag"
    assert user["signals"]["untagged"].any?
    assert_equal "mz4250", user["creators_index"].first["slug"]
  end
end
