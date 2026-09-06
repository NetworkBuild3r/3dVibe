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
      { "kind" => "rename", "summary" => "Ok", "payload" => { "folder_name" => "alpha-one", "to" => "alpha-one-curated" } }
    ]
    out = VibeCurator::ProposalBatch.normalize(items, catalog: @catalog, provider: "xai", budget: 8)
    assert_equal 1, out.size
    assert_equal "alpha-one-curated", out.first["payload"]["to"]
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
    out = VibeCurator::ProposalBatch.normalize(items, catalog: @catalog, provider: "ollama", budget: 3)
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
    first, second = out
    assert_equal "folder looks like audio", first["rationale"]
    assert_equal 0.81, first["confidence"]
    assert_equal 0.81, first["payload"]["confidence"]
    refute first.key?("reason")
    assert_equal "shared creator", second["reason"]
    refute second.key?("confidence")
    refute second["payload"].key?("confidence")
  end

  def test_live_refs_are_stable_for_the_same_suggestion
    item = { "kind" => "tag", "summary" => "Tag it", "payload" => { "model_id" => 12, "tag" => "audio" }, "sidecar_ref" => "random-1" }
    first = VibeCurator::ProposalBatch.normalize([item], catalog: @catalog, provider: "ollama", budget: 1)
    second = VibeCurator::ProposalBatch.normalize([item.merge("sidecar_ref" => "random-2")], catalog: @catalog, provider: "ollama", budget: 1)
    assert_equal first.first["sidecar_ref"], second.first["sidecar_ref"]
    assert first.first["sidecar_ref"].start_with?("ollama:tag:")
  end
end
