# frozen_string_literal: true

require_relative "test_helper"

class RuntimeTest < Minitest::Test
  include CuratorTestHelper

  def llm_payload
    JSON.generate({
      "proposals" => [
        {
          "kind" => "tag",
          "summary" => "Tag Alpha One as audio",
          "payload" => { "model_id" => 12, "folder_name" => "alpha-one", "tag" => "audio", "tags" => ["audio"] }
        }
      ]
    })
  end

  def test_runtime_overrides_env_ollama_url_and_model
    seen = nil
    transport = fake_ollama_transport(llm_payload) do |uri, request|
      seen = [uri.to_s, JSON.parse(request.body)]
    end
    catalog = sample_catalog.merge(
      "curator_runtime" => {
        "provider" => "ollama",
        "ollama_url" => "http://ollama.ui:11434",
        "ollama_model" => "llama-ui"
      }
    )
    env = env_hash(
      "VIBE_CURATOR_PROVIDER" => "stub",
      "VIBE_OLLAMA_URL" => "http://ollama.env:11434",
      "VIBE_OLLAMA_MODEL" => "llama-env"
    )
    result = VibeCurator::Service.proposals(payload: catalog, env: env, transport: transport)

    assert_equal "ollama", result["provider"]
    assert_equal "http://ollama.ui:11434/api/chat", seen[0]
    assert_equal "llama-ui", seen[1]["model"]
    assert_equal "stub", env["VIBE_CURATOR_PROVIDER"]
    assert_equal "http://ollama.env:11434", env["VIBE_OLLAMA_URL"]
  end

  def test_missing_runtime_uses_env
    seen = nil
    transport = fake_openai_transport(llm_payload) do |uri, request|
      seen = [uri.to_s, request["Authorization"]]
    end
    catalog = sample_catalog
    catalog.delete("curator_runtime")
    env = env_hash(
      "VIBE_CURATOR_PROVIDER" => "xai",
      "XAI_API_KEY" => "env-secret-key",
      "XAI_BASE_URL" => "https://api.x.ai/v1"
    )
    result = VibeCurator::Service.proposals(payload: catalog, env: env, transport: transport)

    assert_equal "xai", result["provider"]
    assert_equal "https://api.x.ai/v1/chat/completions", seen[0]
    assert_equal "Bearer env-secret-key", seen[1]
    refute_includes JSON.generate(result), "env-secret-key"
  end

  def test_empty_and_null_runtime_uses_env
    seen = false
    transport = fake_ollama_transport(llm_payload) { seen = true }
    env = env_hash("VIBE_CURATOR_PROVIDER" => "ollama", "VIBE_OLLAMA_URL" => "http://ollama.env:11434")

    [nil, {}, { "provider" => "", "ollama_url" => nil, "xai_api_key" => "" }].each do |runtime|
      catalog = sample_catalog.merge("curator_runtime" => runtime)
      result = VibeCurator::Service.proposals(payload: catalog, env: env, transport: transport)
      assert_equal "ollama", result["provider"], runtime.inspect
    end
    assert seen
  end

  def test_incomplete_runtime_falls_back_field_by_field
    seen = nil
    transport = fake_ollama_transport(llm_payload) do |uri, request|
      seen = [uri.to_s, JSON.parse(request.body)]
    end
    catalog = sample_catalog.merge(
      "curator_runtime" => {
        "provider" => "ollama",
        "ollama_url" => "",
        "ollama_model" => nil
      }
    )
    env = env_hash(
      "VIBE_CURATOR_PROVIDER" => "stub",
      "VIBE_OLLAMA_URL" => "http://ollama.env:11434",
      "VIBE_OLLAMA_MODEL" => "llama-env"
    )
    result = VibeCurator::Service.proposals(payload: catalog, env: env, transport: transport)

    assert_equal "ollama", result["provider"]
    assert_equal "http://ollama.env:11434/api/chat", seen[0]
    assert_equal "llama-env", seen[1]["model"]
  end

  def test_stub_runtime_ignores_provider_keys
    catalog = sample_catalog.merge(
      "provider_hint" => "xai",
      "curator_runtime" => {
        "provider" => "stub",
        "xai_api_key" => "should-not-be-used",
        "openai_api_key" => "openai-should-not-be-used",
        "anthropic_api_key" => "anthropic-should-not-be-used"
      }
    )
    env = env_hash(
      "VIBE_CURATOR_PROVIDER" => "xai",
      "XAI_API_KEY" => "env-secret-key",
      "OPENAI_API_KEY" => "env-openai-key",
      "ANTHROPIC_API_KEY" => "env-anthropic-key"
    )
    result = VibeCurator::Service.proposals(payload: catalog, env: env)

    assert_equal "stub", result["provider"]
    assert result["proposals"].any? { |item| item["sidecar_ref"].start_with?("stub:") }
    dumped = JSON.generate(result)
    refute_includes dumped, "should-not-be-used"
    refute_includes dumped, "openai-should-not-be-used"
    refute_includes dumped, "anthropic-should-not-be-used"
    refute_includes dumped, "env-secret-key"
    refute_includes VibeCurator::Prompt.user_prompt(catalog), "should-not-be-used"
  end

  def test_runtime_maps_openai_and_anthropic_keys_without_mutating_env
    env = env_hash(
      "VIBE_CURATOR_PROVIDER" => "stub",
      "OPENAI_API_KEY" => "env-openai",
      "ANTHROPIC_API_KEY" => "env-anthropic"
    )
    snapshot = env.dup
    catalog = sample_catalog.merge(
      "curator_runtime" => {
        "provider" => "openai",
        "openai_api_key" => "ui-openai-key",
        "anthropic_api_key" => "ui-anthropic-key"
      }
    )
    scoped = VibeCurator::Config.env_with_runtime(catalog, env)
    assert_equal "openai", scoped["VIBE_CURATOR_PROVIDER"]
    assert_equal "ui-openai-key", scoped["OPENAI_API_KEY"]
    assert_equal "ui-anthropic-key", scoped["ANTHROPIC_API_KEY"]
    assert_equal snapshot, env
  end

  def test_provider_switch_mid_process_via_payload
    env = env_hash(
      "VIBE_CURATOR_PROVIDER" => "stub",
      "XAI_API_KEY" => "env-secret-key",
      "VIBE_OLLAMA_URL" => "http://ollama.env:11434",
      "VIBE_OLLAMA_MODEL" => "llama-env"
    )
    snapshot = env.dup
    xai_seen = nil
    ollama_seen = nil

    xai = VibeCurator::Service.proposals(
      payload: sample_catalog.merge(
        "curator_runtime" => { "provider" => "xai", "xai_api_key" => "poll-xai-key" }
      ),
      env: env,
      transport: fake_openai_transport(llm_payload) do |_uri, request|
        xai_seen = request["Authorization"]
      end
    )
    ollama = VibeCurator::Service.proposals(
      payload: sample_catalog.merge(
        "curator_runtime" => {
          "provider" => "ollama",
          "ollama_url" => "http://ollama.poll:11434",
          "ollama_model" => "poll-model"
        }
      ),
      env: env,
      transport: fake_ollama_transport(llm_payload) do |uri, request|
        ollama_seen = [uri.to_s, JSON.parse(request.body)["model"]]
      end
    )
    stub = VibeCurator::Service.proposals(payload: sample_catalog, env: env)

    assert_equal "xai", xai["provider"]
    assert_equal "Bearer poll-xai-key", xai_seen
    assert_equal "ollama", ollama["provider"]
    assert_equal ["http://ollama.poll:11434/api/chat", "poll-model"], ollama_seen
    assert_equal "stub", stub["provider"]
    assert stub["proposals"].any? { |item| item["sidecar_ref"].start_with?("stub:") }
    assert_equal snapshot, env
  end

  def test_runtime_does_not_mutate_process_env
    previous_provider = ENV["VIBE_CURATOR_PROVIDER"]
    previous_key = ENV["XAI_API_KEY"]
    ENV["VIBE_CURATOR_PROVIDER"] = "stub"
    ENV.delete("XAI_API_KEY")

    VibeCurator::Service.proposals(
      payload: sample_catalog.merge(
        "curator_runtime" => { "provider" => "xai", "xai_api_key" => "poll-process-key" }
      ),
      env: ENV,
      transport: fake_openai_transport(llm_payload)
    )

    assert_equal "stub", ENV["VIBE_CURATOR_PROVIDER"]
    assert_nil ENV["XAI_API_KEY"]
  ensure
    if previous_provider.nil?
      ENV.delete("VIBE_CURATOR_PROVIDER")
    else
      ENV["VIBE_CURATOR_PROVIDER"] = previous_provider
    end
    if previous_key.nil?
      ENV.delete("XAI_API_KEY")
    else
      ENV["XAI_API_KEY"] = previous_key
    end
  end

  def test_xai_error_redacts_request_scoped_key
    transport = lambda do |_uri, _request|
      { code: 401, body: "invalid api key poll-xai-key" }
    end
    result = VibeCurator::HTTP.handle(
      method: "POST",
      path: "/proposals",
      headers: { "Authorization" => "Bearer secret" },
      body: JSON.generate(sample_catalog.merge(
        "curator_runtime" => { "provider" => "xai", "xai_api_key" => "poll-xai-key" }
      )),
      env: env_hash("VIBE_CURATOR_PROVIDER" => "stub"),
      transport: transport
    )

    assert_equal 502, result[:status]
    dumped = JSON.generate(result[:body])
    refute_includes dumped, "poll-xai-key"
    assert_includes dumped, "[filtered]"
  end
end
