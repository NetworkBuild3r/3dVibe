# Resolves the request-scoped curator adapter settings sent to the sidecar.
#
# Order: persisted CuratorSetting field when present → else ENV → else stub.
# for_sidecar includes only the decrypted key needed for the active provider.
# The SPA, Meilisearch, and proposal payloads never see this hash.
class CuratorRuntime
  PROVIDERS = CuratorSetting::PROVIDERS
  SECRET_ENV = {
    CuratorSetting::XAI => {
      attribute: :xai_api_key,
      env: %w[XAI_API_KEY VIBE_XAI_API_KEY]
    },
    CuratorSetting::OPENAI => {
      attribute: :openai_api_key,
      env: %w[OPENAI_API_KEY VIBE_OPENAI_API_KEY]
    },
    CuratorSetting::ANTHROPIC => {
      attribute: :anthropic_api_key,
      env: %w[ANTHROPIC_API_KEY VIBE_ANTHROPIC_API_KEY]
    }
  }.freeze

  class << self
    def provider
      present(instance&.provider) || env_provider
    end

    def ollama_url
      present(instance&.ollama_url) || present(ENV["VIBE_OLLAMA_URL"])
    end

    def ollama_model
      present(instance&.ollama_model) || present(ENV["VIBE_OLLAMA_MODEL"])
    end

    def xai_api_key
      secret_for(CuratorSetting::XAI)
    end

    def openai_api_key
      secret_for(CuratorSetting::OPENAI)
    end

    def anthropic_api_key
      secret_for(CuratorSetting::ANTHROPIC)
    end

    def env_provider
      value = ENV["VIBE_CURATOR_PROVIDER"].to_s.strip.downcase
      PROVIDERS.include?(value) ? value : CuratorSetting::STUB
    end

    def as_api
      setting = instance
      {
        provider: setting&.provider.presence || env_provider,
        ollama_url: setting&.ollama_url,
        ollama_model: setting&.ollama_model,
        xai_api_key_status: setting&.xai_api_key_status || "missing",
        openai_api_key_status: setting&.openai_api_key_status || "missing",
        anthropic_api_key_status: setting&.anthropic_api_key_status || "missing"
      }
    end

    # Injected into POST /proposals only. Never log this hash.
    def for_sidecar
      name = provider
      payload = {
        provider: name,
        ollama_url: ollama_url,
        ollama_model: ollama_model
      }
      spec = SECRET_ENV[name]
      if spec
        key = public_send(spec[:attribute])
        payload[spec[:attribute]] = key if key.present?
      end
      payload
    end

    def instance
      CuratorSetting.instance
    end

    private

    def secret_for(provider_name)
      spec = SECRET_ENV.fetch(provider_name)
      present(instance&.public_send(spec[:attribute])) || spec[:env].lazy.map { |name| present(ENV[name]) }.find(&:itself)
    end

    def present(value)
      text = value.to_s.strip
      text.empty? ? nil : text
    end
  end
end
