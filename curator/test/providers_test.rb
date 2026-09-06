# frozen_string_literal: true

require_relative "test_helper"

class ProvidersTest < Minitest::Test
  include CuratorTestHelper

  def llm_payload
    JSON.generate({
      "proposals" => [
        {
          "kind" => "tag",
          "summary" => "Tag Alpha One as audio",
          "rationale" => "title and sample paths look like a horn",
          "confidence" => 0.7,
          "payload" => { "model_id" => 12, "folder_name" => "alpha-one", "tag" => "audio", "tags" => ["audio"] }
        },
        {
          "kind" => "rename",
          "summary" => "Escape the jail",
          "payload" => { "folder_name" => "alpha-one", "to" => "../outside" }
        }
      ]
    })
  end

  def test_ollama_native_api_parses_message_content
    seen = nil
    transport = fake_ollama_transport(llm_payload) do |uri, request|
      seen = [uri.to_s, JSON.parse(request.body)]
    end
    env = env_hash(
      "VIBE_CURATOR_PROVIDER" => "ollama",
      "VIBE_OLLAMA_URL" => "http://ollama.local:11434",
      "VIBE_OLLAMA_MODEL" => "llama3.2"
    )
    result = VibeCurator::Service.proposals(payload: sample_catalog, env: env, transport: transport)

    assert_equal "ollama", result["provider"]
    assert_equal "http://ollama.local:11434/api/chat", seen[0]
    assert_equal "llama3.2", seen[1]["model"]
    assert_equal false, seen[1]["stream"]
    assert_equal "json", seen[1]["format"]
    assert_equal 1, result["proposals"].size
    assert_equal "tag", result["proposals"].first["kind"]
    assert_equal "audio", result["proposals"].first["payload"]["tag"]
    assert_equal "title and sample paths look like a horn", result["proposals"].first["rationale"]
    assert_equal 0.7, result["proposals"].first["confidence"]
  end

  def test_ollama_openai_compatible_url
    seen = nil
    transport = fake_openai_transport(llm_payload) do |uri, request|
      seen = uri.to_s
    end
    env = env_hash(
      "VIBE_CURATOR_PROVIDER" => "ollama",
      "VIBE_OLLAMA_URL" => "http://ollama.local:11434/v1",
      "VIBE_OLLAMA_API" => "openai"
    )
    result = VibeCurator::Service.proposals(payload: sample_catalog, env: env, transport: transport)
    assert_equal "http://ollama.local:11434/v1/chat/completions", seen
    assert_equal "ollama", result["provider"]
    assert_equal 1, result["proposals"].size
  end

  def test_xai_sends_bearer_token_and_parses_chat_completions
    seen = nil
    transport = fake_openai_transport(llm_payload) do |uri, request|
      seen = [uri.to_s, request["Authorization"], JSON.parse(request.body)]
    end
    env = env_hash(
      "VIBE_CURATOR_PROVIDER" => "xai",
      "XAI_API_KEY" => "xai-test-key",
      "XAI_BASE_URL" => "https://api.x.ai/v1",
      "XAI_MODEL" => "grok-4"
    )
    result = VibeCurator::Service.proposals(payload: sample_catalog, env: env, transport: transport)

    assert_equal "xai", result["provider"]
    assert_equal "https://api.x.ai/v1/chat/completions", seen[0]
    assert_equal "Bearer xai-test-key", seen[1]
    assert_equal "grok-4", seen[2]["model"]
    assert_equal 1, result["proposals"].size
    assert result["proposals"].first["sidecar_ref"].start_with?("xai:tag:")
  end

  def test_xai_requires_api_key
    env = env_hash("VIBE_CURATOR_PROVIDER" => "xai", "XAI_API_KEY" => "")
    error = assert_raises(VibeCurator::Error) do
      VibeCurator::Service.proposals(payload: sample_catalog, env: env)
    end
    assert_equal 503, error.status
    assert_equal "xai_not_configured", error.code
  end

  def test_catalog_hint_selects_ollama_when_env_blank
    seen = false
    transport = fake_ollama_transport(llm_payload) { seen = true }
    catalog = sample_catalog.merge("provider_hint" => "ollama")
    result = VibeCurator::Service.proposals(
      payload: catalog,
      env: env_hash("VIBE_CURATOR_PROVIDER" => ""),
      transport: transport
    )
    assert seen
    assert_equal "ollama", result["provider"]
  end
end
