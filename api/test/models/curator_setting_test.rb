require "test_helper"

class CuratorSettingTest < ActiveSupport::TestCase
  test "defaults new records to ollama and gemma4" do
    setting = CuratorSetting.create!
    assert_equal "ollama", setting.provider
    assert_equal "gemma4", setting.ollama_model
    assert_equal CuratorSetting::DEFAULT_PROVIDER, setting.provider
    assert_equal CuratorSetting::DEFAULT_OLLAMA_MODEL, setting.ollama_model
  end

  test "ensure_defaults creates singleton and fills blank model only" do
    created = CuratorSetting.ensure_defaults!
    assert_equal "ollama", created.provider
    assert_equal "gemma4", created.ollama_model

    created.update!(provider: "xai", ollama_model: nil)
    filled = CuratorSetting.ensure_defaults!
    assert_equal created.id, filled.id
    assert_equal "xai", filled.provider
    assert_equal "gemma4", filled.ollama_model
  end

  test "encrypts provider keys at rest and never inspects plaintext" do
    setting = CuratorSetting.create!(
      provider: "xai",
      xai_api_key: "sk-inspect-secret",
      openai_api_key: "sk-openai-secret",
      anthropic_api_key: "sk-anthropic-secret"
    )
    raw = CuratorSetting.connection.select_one("SELECT xai_api_key, openai_api_key, anthropic_api_key FROM curator_settings WHERE id = #{setting.id}")
    refute_includes raw["xai_api_key"].to_s, "sk-inspect-secret"
    refute_includes raw["openai_api_key"].to_s, "sk-openai-secret"
    refute_includes raw["anthropic_api_key"].to_s, "sk-anthropic-secret"
    setting.reload
    assert_equal "sk-inspect-secret", setting.xai_api_key
    assert_equal "sk-openai-secret", setting.openai_api_key
    assert_equal "sk-anthropic-secret", setting.anthropic_api_key
    refute_includes setting.inspect, "sk-inspect-secret"
    refute_includes setting.inspect, "sk-openai-secret"
    refute_includes setting.inspect, "sk-anthropic-secret"
    refute_includes setting.as_json.inspect, "sk-inspect-secret"
    assert_equal "set", setting.xai_api_key_status
    assert_equal "set", setting.openai_api_key_status
    assert_equal "set", setting.anthropic_api_key_status
    refute setting.as_api.key?(:xai_api_key)
    refute setting.as_api.key?(:openai_api_key)
    refute setting.as_api.key?(:anthropic_api_key)
  end

  test "validates provider and stays a singleton" do
    first = CuratorSetting.create!(provider: "stub")
    assert_raises(ActiveRecord::RecordInvalid) { CuratorSetting.create!(provider: "ollama") }
    first.provider = "nope"
    refute first.valid?
    CuratorSetting::PROVIDERS.each do |name|
      first.provider = name
      assert first.valid?, name
    end
  end

  test "runtime prefers persisted fields over env and injects only the active key" do
    ENV["VIBE_CURATOR_PROVIDER"] = "stub"
    ENV["VIBE_OLLAMA_URL"] = "http://env-ollama:11434"
    ENV["VIBE_OLLAMA_MODEL"] = "env-model"
    ENV["XAI_API_KEY"] = "env-xai-key"
    ENV["OPENAI_API_KEY"] = "env-openai-key"
    ENV["ANTHROPIC_API_KEY"] = "env-anthropic-key"

    assert_equal "stub", CuratorRuntime.provider
    runtime = CuratorRuntime.for_sidecar
    assert_equal "stub", runtime[:provider]
    refute runtime.key?(:xai_api_key)
    refute runtime.key?(:openai_api_key)
    refute runtime.key?(:anthropic_api_key)

    CuratorSetting.create!(
      provider: "xai",
      ollama_url: "http://ui-ollama:11434",
      ollama_model: "ui-model",
      xai_api_key: "ui-xai-key",
      openai_api_key: "ui-openai-key",
      anthropic_api_key: "ui-anthropic-key"
    )
    runtime = CuratorRuntime.for_sidecar
    assert_equal "xai", runtime[:provider]
    assert_equal "http://ui-ollama:11434", runtime[:ollama_url]
    assert_equal "ui-model", runtime[:ollama_model]
    assert_equal "ui-xai-key", runtime[:xai_api_key]
    refute runtime.key?(:openai_api_key)
    refute runtime.key?(:anthropic_api_key)
    refute CuratorRuntime.as_api.key?(:xai_api_key)
    assert_equal "set", CuratorRuntime.as_api[:xai_api_key_status]
    assert_equal "set", CuratorRuntime.as_api[:openai_api_key_status]
    assert_equal "set", CuratorRuntime.as_api[:anthropic_api_key_status]

    CuratorSetting.instance.update!(provider: "openai")
    runtime = CuratorRuntime.for_sidecar
    assert_equal "openai", runtime[:provider]
    assert_equal "ui-openai-key", runtime[:openai_api_key]
    refute runtime.key?(:xai_api_key)
    refute runtime.key?(:anthropic_api_key)

    CuratorSetting.instance.update!(provider: "anthropic")
    runtime = CuratorRuntime.for_sidecar
    assert_equal "anthropic", runtime[:provider]
    assert_equal "ui-anthropic-key", runtime[:anthropic_api_key]
    refute runtime.key?(:xai_api_key)
    refute runtime.key?(:openai_api_key)

    CuratorSetting.instance.update!(provider: "ollama")
    runtime = CuratorRuntime.for_sidecar
    assert_equal "ollama", runtime[:provider]
    refute runtime.key?(:xai_api_key)
    refute runtime.key?(:openai_api_key)
    refute runtime.key?(:anthropic_api_key)
  ensure
    ENV.delete("VIBE_CURATOR_PROVIDER")
    ENV.delete("VIBE_OLLAMA_URL")
    ENV.delete("VIBE_OLLAMA_MODEL")
    ENV.delete("XAI_API_KEY")
    ENV.delete("OPENAI_API_KEY")
    ENV.delete("ANTHROPIC_API_KEY")
  end
end
