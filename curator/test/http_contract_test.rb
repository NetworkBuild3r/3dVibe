# frozen_string_literal: true

require_relative "test_helper"

class HTTPContractTest < Minitest::Test
  include CuratorTestHelper

  def test_health_reports_stub_by_default
    result = VibeCurator::HTTP.handle(method: "GET", path: "/health", env: env_hash)
    assert_equal 200, result[:status]
    assert_equal true, result[:body]["ok"]
    assert_equal "3dvibe-curator-stub", result[:body]["service"]
    assert_equal "stub", result[:body]["provider"]
  end

  def test_health_reports_live_provider
    result = VibeCurator::HTTP.handle(method: "GET", path: "/health", env: env_hash("VIBE_CURATOR_PROVIDER" => "ollama"))
    assert_equal "3dvibe-curator", result[:body]["service"]
    assert_equal "ollama", result[:body]["provider"]
  end

  def test_proposals_require_token
    result = VibeCurator::HTTP.handle(
      method: "POST",
      path: "/proposals",
      headers: {},
      body: JSON.generate(sample_catalog),
      env: env_hash
    )
    assert_equal 401, result[:status]
  end

  def test_post_proposals_contract_shape
    result = VibeCurator::HTTP.handle(
      method: "POST",
      path: "/proposals",
      headers: { "Authorization" => "Bearer secret" },
      body: JSON.generate(sample_catalog),
      env: env_hash
    )
    assert_equal 200, result[:status]
    assert_equal "stub", result[:headers]["X-Curator-Provider"]
    body = result[:body]
    assert_equal "stub", body["provider"]
    assert body["proposals"].is_a?(Array)
    refute_empty body["proposals"]
    body["proposals"].each do |item|
      assert_includes VibeCurator::KINDS, item["kind"]
      assert item["summary"].to_s != ""
      assert item["sidecar_ref"].to_s != ""
      assert item["payload"].is_a?(Hash)
    end
  end

  def test_x_curator_token_header
    result = VibeCurator::HTTP.handle(
      method: "POST",
      path: "/proposals",
      headers: { "X-Curator-Token" => "secret" },
      body: JSON.generate(sample_catalog),
      env: env_hash
    )
    assert_equal 200, result[:status]
  end

  def test_get_proposals_lists_library_root
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "signal-horn"))
      File.write(File.join(root, "signal-horn/horn.stl"), "solid x\nendsolid x\n")
      FileUtils.mkdir_p(File.join(root, "key-clip"))
      result = VibeCurator::HTTP.handle(
        method: "GET",
        path: "/proposals",
        headers: { "X-Curator-Token" => "secret" },
        query: { "library_root" => root },
        env: env_hash("LIBRARY_ROOT" => root)
      )
      assert_equal 200, result[:status]
      refs = result[:body]["proposals"].map { |item| item["sidecar_ref"] }
      assert_includes refs, "stub:tag:key-clip"
      assert_includes refs, "stub:rename:key-clip"
    end
  end

  def test_accepts_hardened_catalog_fields
    result = VibeCurator::HTTP.handle(
      method: "POST",
      path: "/proposals",
      headers: { "Authorization" => "Bearer secret" },
      body: JSON.generate(sample_catalog),
      env: env_hash
    )
    assert_equal 200, result[:status]
    tag = result[:body]["proposals"].find { |item| item["kind"] == "tag" }
    assert_equal 12, tag["payload"]["model_id"]
    assert_equal "alpha-one", tag["payload"]["folder_name"]
  end

  def test_xai_misconfig_is_503
    result = VibeCurator::HTTP.handle(
      method: "POST",
      path: "/proposals",
      headers: { "Authorization" => "Bearer secret" },
      body: JSON.generate(sample_catalog),
      env: env_hash("VIBE_CURATOR_PROVIDER" => "xai", "XAI_API_KEY" => "")
    )
    assert_equal 503, result[:status]
    assert_equal "xai_not_configured", result[:body]["error"]
  end

  def test_post_runtime_sets_provider_header
    result = VibeCurator::HTTP.handle(
      method: "POST",
      path: "/proposals",
      headers: { "Authorization" => "Bearer secret" },
      body: JSON.generate(sample_catalog.merge(
        "curator_runtime" => { "provider" => "stub", "xai_api_key" => "should-not-echo" }
      )),
      env: env_hash("VIBE_CURATOR_PROVIDER" => "ollama")
    )
    assert_equal 200, result[:status]
    assert_equal "stub", result[:headers]["X-Curator-Provider"]
    assert_equal "stub", result[:body]["provider"]
    refute_includes JSON.generate(result[:body]), "should-not-echo"
  end

  def test_get_proposals_ignores_runtime_on_query_string
    result = VibeCurator::HTTP.handle(
      method: "GET",
      path: "/proposals",
      headers: { "X-Curator-Token" => "secret" },
      query: {
        "curator_runtime" => JSON.generate("provider" => "xai", "xai_api_key" => "query-secret"),
        "xai_api_key" => "query-secret"
      },
      env: env_hash("VIBE_CURATOR_PROVIDER" => "")
    )
    assert_equal 200, result[:status]
    assert_equal "stub", result[:body]["provider"]
    refute_includes JSON.generate(result[:body]), "query-secret"
  end

  def test_method_not_allowed
    result = VibeCurator::HTTP.handle(
      method: "DELETE",
      path: "/proposals",
      headers: { "Authorization" => "Bearer secret" },
      env: env_hash
    )
    assert_equal 405, result[:status]
  end
end
