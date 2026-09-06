require "test_helper"

class CuratorSettingTest < ActiveSupport::TestCase
  test "encrypts xai_api_key at rest and never inspects plaintext" do
    setting = CuratorSetting.create!(provider: "xai", xai_api_key: "sk-inspect-secret")
    raw = CuratorSetting.connection.select_value("SELECT xai_api_key FROM curator_settings WHERE id = #{setting.id}")
    refute_includes raw.to_s, "sk-inspect-secret"
    assert_equal "sk-inspect-secret", setting.reload.xai_api_key
    refute_includes setting.inspect, "sk-inspect-secret"
    refute_includes setting.as_json.inspect, "sk-inspect-secret"
    assert_equal "set", setting.xai_api_key_status
    refute setting.as_api.key?(:xai_api_key)
  end

  test "validates provider and stays a singleton" do
    first = CuratorSetting.create!(provider: "stub")
    assert_raises(ActiveRecord::RecordInvalid) { CuratorSetting.create!(provider: "ollama") }
    first.provider = "nope"
    refute first.valid?
  end

  test "runtime prefers persisted fields over env" do
    ENV["VIBE_CURATOR_PROVIDER"] = "stub"
    ENV["VIBE_OLLAMA_URL"] = "http://env-ollama:11434"
    ENV["VIBE_OLLAMA_MODEL"] = "env-model"
    ENV["XAI_API_KEY"] = "env-xai-key"

    assert_equal "stub", CuratorRuntime.provider
    runtime = CuratorRuntime.for_sidecar
    assert_equal "stub", runtime[:provider]
    refute runtime.key?(:xai_api_key)

    CuratorSetting.create!(
      provider: "xai",
      ollama_url: "http://ui-ollama:11434",
      ollama_model: "ui-model",
      xai_api_key: "ui-xai-key"
    )
    runtime = CuratorRuntime.for_sidecar
    assert_equal "xai", runtime[:provider]
    assert_equal "http://ui-ollama:11434", runtime[:ollama_url]
    assert_equal "ui-model", runtime[:ollama_model]
    assert_equal "ui-xai-key", runtime[:xai_api_key]
    refute CuratorRuntime.as_api.key?(:xai_api_key)
    assert_equal "set", CuratorRuntime.as_api[:xai_api_key_status]
  ensure
    ENV.delete("VIBE_CURATOR_PROVIDER")
    ENV.delete("VIBE_OLLAMA_URL")
    ENV.delete("VIBE_OLLAMA_MODEL")
    ENV.delete("XAI_API_KEY")
  end
end
