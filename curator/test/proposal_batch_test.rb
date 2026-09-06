# frozen_string_literal: true

require_relative "test_helper"

class ProposalBatchTest < Minitest::Test
  include CuratorTestHelper

  def setup
    @catalog = sample_catalog
  end

  def test_drops_unknown_kinds_and_deletes
    items = [
      { "kind" => "delete", "summary" => "Delete junk", "payload" => { "folder_name" => "alpha-one" } },
      { "kind" => "tag", "summary" => "Zap", "payload" => { "folder_name" => "alpha-one", "delete" => true, "tag" => "x" } },
      { "kind" => "explode", "summary" => "Nope", "payload" => {} },
      { "kind" => "tag", "summary" => "Keep", "payload" => { "model_id" => 12, "folder_name" => "alpha-one", "tag" => "audio" } }
    ]
    out = VibeCurator::ProposalBatch.normalize(items, catalog: @catalog, provider: "ollama", budget: 8)
    assert_equal 1, out.size
    assert_equal "tag", out.first["kind"]
    assert out.first["sidecar_ref"].start_with?("ollama:tag:")
  end

  def test_rejects_escaping_and_nested_rename_destinations
    items = [
      { "kind" => "rename", "summary" => "Escape", "payload" => { "folder_name" => "alpha-one", "to" => "../etc" } },
      { "kind" => "move", "summary" => "Nested", "payload" => { "from" => "alpha-one", "to" => "kits/nested" } },
      { "kind" => "rename", "summary" => "Hidden", "payload" => { "folder_name" => "alpha-one", "to" => ".hidden" } },
      { "kind" => "rename", "summary" => "Ok", "payload" => { "folder_name" => "alpha-one", "to" => "alpha-horn" } }
    ]
    out = VibeCurator::ProposalBatch.normalize(items, catalog: @catalog, provider: "xai", budget: 8)
    assert_equal 1, out.size
    assert_equal "alpha-horn", out.first["payload"]["to"]
  end

  def test_jails_relative_move_paths
    items = [
      {
        "kind" => "move",
        "summary" => "Move file",
        "payload" => {
          "model_id" => 12,
          "folder_name" => "alpha-one",
          "relative_path" => "alpha-one/../secret.stl",
          "destination_folder" => "beta-two"
        }
      },
      {
        "kind" => "move",
        "summary" => "Move jailed file",
        "payload" => {
          "model_id" => 12,
          "folder_name" => "alpha-one",
          "relative_path" => "horn.stl",
          "destination_folder" => "beta-two"
        }
      }
    ]
    out = VibeCurator::ProposalBatch.normalize(items, catalog: @catalog, provider: "ollama", budget: 8)
    assert_equal 1, out.size
    assert_equal "horn.stl", out.first["payload"]["relative_path"]
    assert_equal "beta-two", out.first["payload"]["destination_folder"]
  end

  def test_budget_caps_batch
    items = (1..12).map do |i|
      { "kind" => "tag", "summary" => "Tag #{i}", "payload" => { "model_id" => i, "tag" => "n#{i}" } }
    end
    # Stub keeps insertion order + budget only (CI fixtures).
    out = VibeCurator::ProposalBatch.normalize(items, catalog: @catalog, provider: "stub", budget: 3)
    assert_equal 3, out.size
  end

  def test_passes_through_rationale_and_confidence_without_inventing
    items = [
      {
        "kind" => "tag",
        "summary" => "Tag it",
        "rationale" => "folder looks like audio",
        "confidence" => 0.81,
        "payload" => { "model_id" => 12, "folder_name" => "alpha-one", "tag" => "audio" }
      },
      {
        "kind" => "organize",
        "summary" => "Shelf",
        "reason" => "shared creator",
        "payload" => { "shelf" => "mz4250", "model_ids" => [12] }
      }
    ]
    out = VibeCurator::ProposalBatch.normalize(items, catalog: @catalog, provider: "xai", budget: 8)
    tagged = out.find { |item| item["kind"] == "tag" }
    organized = out.find { |item| item["kind"] == "organize" }
    assert tagged
    assert organized
    assert_equal "folder looks like audio", tagged["rationale"]
    assert_equal 0.81, tagged["confidence"]
    assert_equal 0.81, tagged["payload"]["confidence"]
    refute tagged.key?("reason")
    assert_equal "shared creator", organized["reason"]
    refute organized.key?("confidence")
    refute organized["payload"].key?("confidence")
  end

  def test_live_refs_are_stable_for_the_same_suggestion
    item = { "kind" => "tag", "summary" => "Tag it", "payload" => { "model_id" => 12, "tag" => "audio" }, "sidecar_ref" => "random-1" }
    first = VibeCurator::ProposalBatch.normalize([item], catalog: @catalog, provider: "ollama", budget: 1)
    second = VibeCurator::ProposalBatch.normalize([item.merge("sidecar_ref" => "random-2")], catalog: @catalog, provider: "ollama", budget: 1)
    assert_equal first.first["sidecar_ref"], second.first["sidecar_ref"]
    assert first.first["sidecar_ref"].start_with?("ollama:tag:")
  end

  def test_live_batch_prefers_high_signal_kinds_and_drops_spam
    items = [
      { "kind" => "tag", "summary" => "Format tag", "payload" => { "model_id" => 12, "folder_name" => "alpha-one", "tag" => "stl" } },
      { "kind" => "tag", "summary" => "Already tagged", "payload" => { "model_id" => 12, "tag" => "stl" } },
      { "kind" => "tag", "summary" => "Invented model", "payload" => { "model_id" => 999, "tag" => "dragon" } },
      { "kind" => "rename", "summary" => "Generic curated suffix", "payload" => { "folder_name" => "alpha-one", "to" => "alpha-one-curated" } },
      { "kind" => "move", "summary" => "Generic shelf", "payload" => { "from" => "beta-two", "to" => "beta-two-shelf" } },
      { "kind" => "tag", "summary" => "Creator tag", "payload" => { "model_id" => 13, "folder_name" => "beta-two", "tag" => "mz4250" } },
      { "kind" => "organize", "summary" => "Shelf by creator", "payload" => { "shelf" => "mz4250", "model_ids" => [12, 13] } },
      {
        "kind" => "merge",
        "summary" => "Merge related folders",
        "payload" => { "source_id" => 12, "target_id" => 13, "from" => "alpha-one", "to" => "beta-two" }
      }
    ]
    out = VibeCurator::ProposalBatch.normalize(items, catalog: @catalog, provider: "ollama", budget: 8, env: env_hash)
    kinds = out.map { |item| item["kind"] }
    summaries = out.map { |item| item["summary"] }

    assert_includes kinds, "merge"
    assert_includes kinds, "organize"
    assert_includes kinds, "tag"
    assert_includes summaries, "Creator tag"
    refute_includes summaries, "Format tag"
    refute_includes summaries, "Already tagged"
    refute_includes summaries, "Invented model"
    refute_includes summaries, "Generic curated suffix"
    refute_includes summaries, "Generic shelf"
    assert kinds.first(2).all? { |kind| %w[merge organize].include?(kind) }
  end

  def test_live_batch_enforces_max_per_kind
    items = (1..6).map do |i|
      { "kind" => "tag", "summary" => "Tag subject #{i}", "payload" => { "model_id" => 13, "folder_name" => "beta-two", "tag" => "subject-#{i}" } }
    end
    env = env_hash("VIBE_CURATOR_MAX_PER_KIND" => "2")
    out = VibeCurator::ProposalBatch.normalize(items, catalog: @catalog, provider: "xai", budget: 8, env: env)
    assert_equal 2, out.size
    assert out.all? { |item| item["kind"] == "tag" }
  end

  def test_live_batch_drops_low_confidence_only_when_present
    items = [
      {
        "kind" => "tag",
        "summary" => "Low",
        "confidence" => 0.2,
        "payload" => { "model_id" => 13, "folder_name" => "beta-two", "tag" => "weak" }
      },
      {
        "kind" => "tag",
        "summary" => "High",
        "confidence" => 0.9,
        "payload" => { "model_id" => 13, "folder_name" => "beta-two", "tag" => "strong" }
      },
      {
        "kind" => "tag",
        "summary" => "Unscored",
        "payload" => { "model_id" => 13, "folder_name" => "beta-two", "tag" => "plain" }
      }
    ]
    env = env_hash("VIBE_CURATOR_MIN_CONFIDENCE" => "0.5")
    out = VibeCurator::ProposalBatch.normalize(items, catalog: @catalog, provider: "ollama", budget: 8, env: env)
    summaries = out.map { |item| item["summary"] }
    assert_includes summaries, "High"
    assert_includes summaries, "Unscored"
    refute_includes summaries, "Low"
  end

  def test_confidence_out_of_range_is_omitted_not_invented
    items = [
      {
        "kind" => "tag",
        "summary" => "Percent leftover",
        "confidence" => 81,
        "payload" => { "model_id" => 12, "folder_name" => "alpha-one", "tag" => "audio" }
      }
    ]
    out = VibeCurator::ProposalBatch.normalize(items, catalog: @catalog, provider: "ollama", budget: 8, env: env_hash)
    assert_equal 1, out.size
    refute out.first.key?("confidence")
    refute out.first["payload"].key?("confidence")
    refute out.first.key?("rationale")
  end

  def test_payload_only_rationale_and_confidence_are_lifted
    items = [
      {
        "kind" => "tag",
        "summary" => "From payload",
        "payload" => {
          "model_id" => 12,
          "folder_name" => "alpha-one",
          "tag" => "audio",
          "rationale" => "sample_paths include horn.stl",
          "confidence" => 0.64
        }
      }
    ]
    out = VibeCurator::ProposalBatch.normalize(items, catalog: @catalog, provider: "xai", budget: 8, env: env_hash)
    assert_equal "sample_paths include horn.stl", out.first["rationale"]
    assert_equal 0.64, out.first["confidence"]
    assert_equal 0.64, out.first["payload"]["confidence"]
  end

  def test_stub_ignores_quality_knobs
    items = [
      { "kind" => "tag", "summary" => "Format tag", "sidecar_ref" => "stub:tag:alpha-one", "payload" => { "model_id" => 12, "tag" => "stl" } },
      { "kind" => "rename", "summary" => "Curated", "sidecar_ref" => "stub:rename:alpha-one", "payload" => { "folder_name" => "alpha-one", "to" => "alpha-one-curated" } }
    ]
    env = env_hash("VIBE_CURATOR_MAX_PER_KIND" => "1", "VIBE_CURATOR_MIN_CONFIDENCE" => "0.9")
    out = VibeCurator::ProposalBatch.normalize(items, catalog: @catalog, provider: "stub", budget: 8, env: env)
    assert_equal %w[tag rename], out.map { |item| item["kind"] }
    assert_equal "stub:tag:alpha-one", out.first["sidecar_ref"]
  end
end
