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
    assert_equal "missing", body["openai_api_key_status"]
    assert_equal "missing", body["anthropic_api_key_status"]
    refute body.key?("xai_api_key")
    refute body.key?("openai_api_key")
    refute body.key?("anthropic_api_key")
    refute_includes response.body, "xai_api_key\""
    refute_includes response.body, "openai_api_key\""
    refute_includes response.body, "anthropic_api_key\""
  end

  test "first patch seeds ollama and gemma4 when those fields are omitted" do
    patch "/api/v1/curator_settings",
          params: { ollama_url: "http://ollama.local:11434" },
          headers: auth_header(@owner),
          as: :json
    assert_response :success
    body = response.parsed_body.fetch("curator_setting")
    assert_equal "ollama", body["provider"]
    assert_equal "gemma4", body["ollama_model"]
    assert_equal "http://ollama.local:11434", body["ollama_url"]
    assert_equal "ollama", CuratorSetting.instance.provider
    assert_equal "gemma4", CuratorSetting.instance.ollama_model
  end

  test "owner can patch provider and ollama fields including openai and anthropic" do
    patch "/api/v1/curator_settings",
          params: { provider: "ollama", ollama_url: "http://ollama.local:11434", ollama_model: "gemma4" },
          headers: auth_header(@owner),
          as: :json
    assert_response :success
    body = response.parsed_body.fetch("curator_setting")
    assert_equal "ollama", body["provider"]
    assert_equal "http://ollama.local:11434", body["ollama_url"]
    assert_equal "gemma4", body["ollama_model"]
    assert_equal "missing", body["xai_api_key_status"]
    assert_equal "missing", body["openai_api_key_status"]
    assert_equal "missing", body["anthropic_api_key_status"]
    refute body.key?("xai_api_key")

    setting = CuratorSetting.instance
    assert_equal "ollama", setting.provider
    assert_nil setting.xai_api_key

    %w[openai anthropic].each do |name|
      patch "/api/v1/curator_settings",
            params: { provider: name },
            headers: auth_header(@owner),
            as: :json
      assert_response :success
      assert_equal name, response.parsed_body.dig("curator_setting", "provider")
    end
  end

  test "contributor and viewer are forbidden" do
    get "/api/v1/curator_settings", headers: auth_header(@contributor), as: :json
    assert_response :forbidden

    patch "/api/v1/curator_settings",
          params: { provider: "xai" },
          headers: auth_header(@viewer),
          as: :json
    assert_response :forbidden

    {
      "xai_api_key" => "should-not-store-xai",
      "openai_api_key" => "should-not-store-openai",
      "anthropic_api_key" => "should-not-store-anthropic"
    }.each do |path, value|
      put "/api/v1/curator_settings/#{path}",
          params: { path => value },
          headers: auth_header(@contributor),
          as: :json
      assert_response :forbidden
      assert_nil CuratorSetting.instance

      delete "/api/v1/curator_settings/#{path}", headers: auth_header(@viewer), as: :json
      assert_response :forbidden
    end
  end

  test "put sets encrypted keys and never echoes them; delete clears" do
    {
      "xai_api_key" => "sk-live-secret-do-not-echo",
      "openai_api_key" => "sk-openai-secret-do-not-echo",
      "anthropic_api_key" => "sk-anthropic-secret-do-not-echo"
    }.each do |attribute, secret|
      put "/api/v1/curator_settings/#{attribute}",
          params: { attribute => secret },
          headers: auth_header(@owner),
          as: :json
      assert_response :success, attribute
      body = response.parsed_body.fetch("curator_setting")
      assert_equal "set", body["#{attribute}_status"]
      refute_includes response.body, secret
      refute body.key?(attribute)

      setting = CuratorSetting.instance
      assert_equal secret, setting.public_send(attribute)
      raw = CuratorSetting.connection.select_value("SELECT #{attribute} FROM curator_settings WHERE id = #{setting.id}")
      refute_includes raw.to_s, secret
    end

    get "/api/v1/curator_settings", headers: auth_header(@owner), as: :json
    assert_response :success
    body = response.parsed_body.fetch("curator_setting")
    assert_equal "set", body["xai_api_key_status"]
    assert_equal "set", body["openai_api_key_status"]
    assert_equal "set", body["anthropic_api_key_status"]
    refute_includes response.body, "sk-live-secret-do-not-echo"
    refute_includes response.body, "sk-openai-secret-do-not-echo"
    refute_includes response.body, "sk-anthropic-secret-do-not-echo"

    %w[xai_api_key openai_api_key anthropic_api_key].each do |attribute|
      delete "/api/v1/curator_settings/#{attribute}", headers: auth_header(@owner), as: :json
      assert_response :success
      assert_equal "missing", response.parsed_body.dig("curator_setting", "#{attribute}_status")
      assert_nil CuratorSetting.instance.reload.public_send(attribute)
    end
  end

  test "rejects unknown provider and blank keys" do
    patch "/api/v1/curator_settings",
          params: { provider: "spark" },
          headers: auth_header(@owner),
          as: :json
    assert_response :unprocessable_entity

    %w[xai_api_key openai_api_key anthropic_api_key].each do |attribute|
      put "/api/v1/curator_settings/#{attribute}",
          params: { attribute => "   " },
          headers: auth_header(@owner),
          as: :json
      assert_response :unprocessable_entity
      assert_nil CuratorSetting.instance&.public_send(attribute)
    end
  end

  test "patch does not accept raw secrets" do
    patch "/api/v1/curator_settings",
          params: {
            provider: "openai",
            openai_api_key: "sk-should-not-persist",
            xai_api_key: "sk-xai-should-not-persist",
            anthropic_api_key: "sk-anthropic-should-not-persist"
          },
          headers: auth_header(@owner),
          as: :json
    assert_response :success
    setting = CuratorSetting.instance
    assert_equal "openai", setting.provider
    assert_nil setting.openai_api_key
    assert_nil setting.xai_api_key
    assert_nil setting.anthropic_api_key
    refute_includes response.body, "sk-should-not-persist"
  end

  test "provider secrets are filtered from request logs" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    filtered = filter.filter(
      "xai_api_key" => "sk-filter-me",
      "openai_api_key" => "sk-openai-filter-me",
      "anthropic_api_key" => "sk-anthropic-filter-me",
      "provider" => "xai",
      "curator_runtime" => { "provider" => "openai", "openai_api_key" => "sk-openai-filter-me" }
    )

    assert_equal "[FILTERED]", filtered["xai_api_key"]
    assert_equal "[FILTERED]", filtered["openai_api_key"]
    assert_equal "[FILTERED]", filtered["anthropic_api_key"]
    assert_equal "xai", filtered["provider"]
    assert_equal "[FILTERED]", filtered["curator_runtime"]
    %w[xai_api_key openai_api_key anthropic_api_key].each do |name|
      assert Rails.application.config.filter_parameters.any? { |item| item.to_s.include?(name) }
    end
  end
end
