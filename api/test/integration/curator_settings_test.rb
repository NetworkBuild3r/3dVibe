require "test_helper"

class CuratorSettingsTest < ActionDispatch::IntegrationTest
  def setup
    @owner = create_owner!
    @library = Library.create!(name: "Studio", root_path: "/tmp/curator-settings-#{SecureRandom.hex(4)}")
    Membership.create!(user: @owner, library: @library, role: Membership::OWNER)
    @contributor = create_user!(email: "contrib@example.test")
    Membership.create!(user: @contributor, library: @library, role: Membership::CONTRIBUTOR)
    @viewer = create_user!(email: "viewer@example.test")
    Membership.create!(user: @viewer, library: @library, role: Membership::VIEWER)
  end

  test "owner can get default settings without a stored row" do
    get "/api/v1/curator_settings", headers: auth_header(@owner), as: :json
    assert_response :success
    body = response.parsed_body.fetch("curator_setting")
    assert_equal "stub", body["provider"]
    assert_nil body["ollama_url"]
    assert_nil body["ollama_model"]
    assert_equal "missing", body["xai_api_key_status"]
    refute body.key?("xai_api_key")
    refute_includes response.body, "xai_api_key\""
  end

  test "owner can patch provider and ollama fields" do
    patch "/api/v1/curator_settings",
          params: { provider: "ollama", ollama_url: "http://ollama.local:11434", ollama_model: "llama3.2" },
          headers: auth_header(@owner),
          as: :json
    assert_response :success
    body = response.parsed_body.fetch("curator_setting")
    assert_equal "ollama", body["provider"]
    assert_equal "http://ollama.local:11434", body["ollama_url"]
    assert_equal "llama3.2", body["ollama_model"]
    assert_equal "missing", body["xai_api_key_status"]
    refute body.key?("xai_api_key")

    setting = CuratorSetting.instance
    assert_equal "ollama", setting.provider
    assert_nil setting.xai_api_key
  end

  test "contributor and viewer are forbidden" do
    get "/api/v1/curator_settings", headers: auth_header(@contributor), as: :json
    assert_response :forbidden

    patch "/api/v1/curator_settings",
          params: { provider: "xai" },
          headers: auth_header(@viewer),
          as: :json
    assert_response :forbidden

    put "/api/v1/curator_settings/xai_api_key",
        params: { xai_api_key: "should-not-store" },
        headers: auth_header(@contributor),
        as: :json
    assert_response :forbidden
    assert_nil CuratorSetting.instance

    delete "/api/v1/curator_settings/xai_api_key", headers: auth_header(@viewer), as: :json
    assert_response :forbidden
  end

  test "put sets encrypted key and never echoes it; delete clears" do
    put "/api/v1/curator_settings/xai_api_key",
        params: { xai_api_key: "sk-live-secret-do-not-echo" },
        headers: auth_header(@owner),
        as: :json
    assert_response :success
    body = response.parsed_body.fetch("curator_setting")
    assert_equal "set", body["xai_api_key_status"]
    refute_includes response.body, "sk-live-secret-do-not-echo"
    refute body.key?("xai_api_key")

    setting = CuratorSetting.instance
    assert_equal "sk-live-secret-do-not-echo", setting.xai_api_key
    raw = CuratorSetting.connection.select_value("SELECT xai_api_key FROM curator_settings WHERE id = #{setting.id}")
    refute_includes raw.to_s, "sk-live-secret-do-not-echo"

    get "/api/v1/curator_settings", headers: auth_header(@owner), as: :json
    assert_response :success
    assert_equal "set", response.parsed_body.dig("curator_setting", "xai_api_key_status")
    refute_includes response.body, "sk-live-secret-do-not-echo"

    delete "/api/v1/curator_settings/xai_api_key", headers: auth_header(@owner), as: :json
    assert_response :success
    assert_equal "missing", response.parsed_body.dig("curator_setting", "xai_api_key_status")
    refute_includes response.body, "sk-live-secret-do-not-echo"
    assert_nil CuratorSetting.instance.reload.xai_api_key
  end

  test "rejects unknown provider and blank xai key" do
    patch "/api/v1/curator_settings",
          params: { provider: "spark" },
          headers: auth_header(@owner),
          as: :json
    assert_response :unprocessable_entity

    put "/api/v1/curator_settings/xai_api_key",
        params: { xai_api_key: "   " },
        headers: auth_header(@owner),
        as: :json
    assert_response :unprocessable_entity
    assert_nil CuratorSetting.instance&.xai_api_key
  end

  test "xai_api_key is filtered from request logs" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    filtered = filter.filter(
      "xai_api_key" => "sk-filter-me",
      "provider" => "xai",
      "curator_runtime" => { "provider" => "xai", "xai_api_key" => "sk-filter-me" }
    )

    assert_equal "[FILTERED]", filtered["xai_api_key"]
    assert_equal "xai", filtered["provider"]
    assert_equal "[FILTERED]", filtered["curator_runtime"]
    assert Rails.application.config.filter_parameters.any? { |item| item.to_s.include?("xai_api_key") }
  end
end
