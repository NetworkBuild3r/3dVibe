# frozen_string_literal: true

require_relative "test_helper"

class StubContractTest < Minitest::Test
  include CuratorTestHelper

  def test_stub_emits_deterministic_kinds_and_refs
    result = VibeCurator::Service.proposals(payload: sample_catalog, env: env_hash)
    proposals = result["proposals"]

    assert_equal "stub", result["provider"]
    kinds = proposals.map { |item| item["kind"] }
    assert_includes kinds, "tag"
    assert_includes kinds, "rename"
    assert_includes kinds, "move"
    assert_includes kinds, "merge"
    assert_includes kinds, "organize"
    assert kinds.all? { |kind| VibeCurator::KINDS.include?(kind) }

    refs = proposals.map { |item| item["sidecar_ref"] }
    assert_equal refs.uniq, refs
    assert_includes refs, "stub:tag:alpha-one"
    assert_includes refs, "stub:rename:alpha-one"
    assert_includes refs, "stub:move:beta-two"
    assert_includes refs, "stub:merge:alpha-one:beta-two"
    assert_includes refs, "stub:organize:fixture"
  end

  def test_stub_is_idempotent
    first = VibeCurator::Service.proposals(payload: sample_catalog, env: env_hash)
    second = VibeCurator::Service.proposals(payload: sample_catalog, env: env_hash)
    assert_equal first["proposals"], second["proposals"]
  end

  def test_stub_omits_invented_confidence_and_rationale
    result = VibeCurator::Service.proposals(payload: sample_catalog, env: env_hash)
    result["proposals"].each do |item|
      refute item.key?("confidence")
      refute item.key?("rationale")
      refute item.key?("reason")
      refute item.key?("explanation")
      refute item["payload"].key?("confidence")
    end
  end

  def test_provider_env_stub_wins_over_catalog_hint
    catalog = sample_catalog.merge("provider_hint" => "ollama")
    result = VibeCurator::Service.proposals(payload: catalog, env: env_hash("VIBE_CURATOR_PROVIDER" => "stub"))
    assert_equal "stub", result["provider"]
    assert result["proposals"].any? { |item| item["sidecar_ref"].start_with?("stub:") }
  end

  def test_blank_provider_falls_back_to_catalog_hint_then_stub
    catalog = sample_catalog.merge("provider_hint" => "")
    result = VibeCurator::Service.proposals(payload: catalog, env: env_hash("VIBE_CURATOR_PROVIDER" => ""))
    assert_equal "stub", result["provider"]
  end
end
