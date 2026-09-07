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

  def test_curator_runtime_overrides_env_and_supplies_xai_key
    seen = nil
    transport = fake_openai_transport(llm_payload) do |uri, request|
      seen = [uri.to_s, request["Authorization"], request.body.to_s]
    end
    catalog = sample_catalog.merge(
      "provider_hint" => "stub",
      "curator_runtime" => {
        "provider" => "xai",
        "ollama_url" => "http://ollama.ui:11434",
        "ollama_model" => "llama-ui",
        "xai_api_key" => "ui-secret-key"
      }
    )
    env = env_hash("VIBE_CURATOR_PROVIDER" => "stub", "XAI_API_KEY" => "")
    result = VibeCurator::Service.proposals(payload: catalog, env: env, transport: transport)

    assert_equal "xai", result["provider"]
    assert_equal "Bearer ui-secret-key", seen[1]
    refute_includes seen[2], "ui-secret-key"
    refute_includes VibeCurator::Prompt.user_prompt(catalog), "ui-secret-key"
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

  def test_ollama_defaults_to_gemma4
    seen = nil
    transport = fake_ollama_transport(llm_payload) do |_uri, request|
      seen = JSON.parse(request.body)
    end
    env = env_hash(
      "VIBE_CURATOR_PROVIDER" => "ollama",
      "VIBE_OLLAMA_URL" => "http://ollama.local:11434"
    )
    result = VibeCurator::Service.proposals(payload: sample_catalog, env: env, transport: transport)

    assert_equal "ollama", result["provider"]
    assert_equal "gemma4", seen["model"]
  end

  def test_openai_sends_bearer_token_and_parses_chat_completions
    seen = nil
    transport = fake_openai_transport(llm_payload) do |uri, request|
      seen = [uri.to_s, request["Authorization"], JSON.parse(request.body)]
    end
    env = env_hash(
      "VIBE_CURATOR_PROVIDER" => "openai",
      "OPENAI_API_KEY" => "openai-test-key",
      "OPENAI_BASE_URL" => "https://api.openai.com/v1",
      "OPENAI_MODEL" => "gpt-4o"
    )
    result = VibeCurator::Service.proposals(payload: sample_catalog, env: env, transport: transport)

    assert_equal "openai", result["provider"]
    assert_equal "https://api.openai.com/v1/chat/completions", seen[0]
    assert_equal "Bearer openai-test-key", seen[1]
    assert_equal "gpt-4o", seen[2]["model"]
    assert_equal 1, result["proposals"].size
    assert result["proposals"].first["sidecar_ref"].start_with?("openai:tag:")
  end

  def test_openai_requires_api_key
    env = env_hash("VIBE_CURATOR_PROVIDER" => "openai", "OPENAI_API_KEY" => "")
    error = assert_raises(VibeCurator::Error) do
      VibeCurator::Service.proposals(payload: sample_catalog, env: env)
    end
    assert_equal 503, error.status
    assert_equal "openai_not_configured", error.code
  end

  def test_xai_and_openai_share_openai_compat_and_read_vibe_aliases
    assert_instance_of VibeCurator::Providers::OpenAICompat, VibeCurator::Providers.build("xai")
    assert_instance_of VibeCurator::Providers::OpenAICompat, VibeCurator::Providers.build("openai")
    refute_kind_of VibeCurator::Providers::OpenAICompat, VibeCurator::Providers.build("anthropic")
    refute_kind_of VibeCurator::Providers::OpenAICompat, VibeCurator::Providers.build("ollama")

    seen = nil
    transport = fake_openai_transport(llm_payload) do |uri, request|
      seen = [uri.to_s, request["Authorization"], JSON.parse(request.body)]
    end
    env = env_hash(
      "VIBE_CURATOR_PROVIDER" => "openai",
      "VIBE_OPENAI_API_KEY" => "vibe-openai-key",
      "VIBE_OPENAI_BASE_URL" => "https://compat.example/v1",
      "VIBE_OPENAI_MODEL" => "gpt-alias"
    )
    result = VibeCurator::Service.proposals(payload: sample_catalog, env: env, transport: transport)

    assert_equal "openai", result["provider"]
    assert_equal "https://compat.example/v1/chat/completions", seen[0]
    assert_equal "Bearer vibe-openai-key", seen[1]
    assert_equal "gpt-alias", seen[2]["model"]
  end

  def test_anthropic_sends_messages_api_and_parses_content_blocks
    seen = nil
    transport = fake_anthropic_transport(llm_payload) do |uri, request|
      seen = [uri.to_s, request["x-api-key"], request["anthropic-version"], request["Authorization"], JSON.parse(request.body)]
    end
    env = env_hash(
      "VIBE_CURATOR_PROVIDER" => "anthropic",
      "ANTHROPIC_API_KEY" => "anthropic-test-key",
      "ANTHROPIC_BASE_URL" => "https://api.anthropic.com",
      "ANTHROPIC_MODEL" => "claude-sonnet-4-5"
    )
    result = VibeCurator::Service.proposals(payload: sample_catalog, env: env, transport: transport)

    assert_equal "anthropic", result["provider"]
    assert_equal "https://api.anthropic.com/v1/messages", seen[0]
    assert_equal "anthropic-test-key", seen[1]
    assert_equal "2023-06-01", seen[2]
    assert_nil seen[3]
    assert_equal "claude-sonnet-4-5", seen[4]["model"]
    assert_equal 4096, seen[4]["max_tokens"]
    assert_includes seen[4]["system"], "3dvibe live curator"
    assert seen[4]["messages"].none? { |message| message["role"] == "system" }
    assert_equal 1, result["proposals"].size
    assert result["proposals"].first["sidecar_ref"].start_with?("anthropic:tag:")
  end

  def test_anthropic_requires_api_key
    env = env_hash("VIBE_CURATOR_PROVIDER" => "anthropic", "ANTHROPIC_API_KEY" => "")
    error = assert_raises(VibeCurator::Error) do
      VibeCurator::Service.proposals(payload: sample_catalog, env: env)
    end
    assert_equal 503, error.status
    assert_equal "anthropic_not_configured", error.code
  end

  def test_unknown_env_provider_does_not_silently_stub
    error = assert_raises(VibeCurator::Error) do
      VibeCurator::Service.proposals(
        payload: sample_catalog,
        env: env_hash("VIBE_CURATOR_PROVIDER" => "gemini")
      )
    end
    assert_equal 503, error.status
    assert_equal "unknown_provider", error.code
    assert_match(/gemini/, error.message)
    refute_includes error.message, 'provider "stub"'
  end

  def test_unknown_runtime_provider_does_not_silently_stub
    error = assert_raises(VibeCurator::Error) do
      VibeCurator::Service.proposals(
        payload: sample_catalog.merge("curator_runtime" => { "provider" => "grok" }),
        env: env_hash("VIBE_CURATOR_PROVIDER" => "ollama")
      )
    end
    assert_equal 503, error.status
    assert_equal "unknown_provider", error.code
    assert_match(/grok/, error.message)
  end

  def test_curator_runtime_supplies_openai_and_anthropic_keys
    openai_seen = nil
    anthropic_seen = nil
    env = env_hash("VIBE_CURATOR_PROVIDER" => "stub")

    openai = VibeCurator::Service.proposals(
      payload: sample_catalog.merge(
        "curator_runtime" => { "provider" => "openai", "openai_api_key" => "ui-openai-key" }
      ),
      env: env,
      transport: fake_openai_transport(llm_payload) do |_uri, request|
        openai_seen = [request["Authorization"], request.body.to_s]
      end
    )
    anthropic = VibeCurator::Service.proposals(
      payload: sample_catalog.merge(
        "curator_runtime" => { "provider" => "anthropic", "anthropic_api_key" => "ui-anthropic-key" }
      ),
      env: env,
      transport: fake_anthropic_transport(llm_payload) do |_uri, request|
        anthropic_seen = [request["x-api-key"], request.body.to_s]
      end
    )

    assert_equal "openai", openai["provider"]
    assert_equal "Bearer ui-openai-key", openai_seen[0]
    refute_includes openai_seen[1], "ui-openai-key"
    assert_equal "anthropic", anthropic["provider"]
    assert_equal "ui-anthropic-key", anthropic_seen[0]
    refute_includes anthropic_seen[1], "ui-anthropic-key"
  end
end
