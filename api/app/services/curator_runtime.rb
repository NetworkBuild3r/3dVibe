# Resolves the request-scoped curator adapter settings sent to the sidecar.
#
# Order: persisted CuratorSetting field when present → else ENV → else stub.
# The decrypted xAI key is only placed on `for_sidecar` when provider is xai.
# The SPA, Meilisearch, and proposal payloads never see this hash.
class CuratorRuntime
  PROVIDERS = CuratorSetting::PROVIDERS

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
      present(instance&.xai_api_key) || present(ENV["XAI_API_KEY"]) || present(ENV["VIBE_XAI_API_KEY"])
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
        xai_api_key_status: setting&.xai_api_key_status || "missing"
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
      payload[:xai_api_key] = xai_api_key if name == CuratorSetting::XAI && xai_api_key.present?
      payload
    end

    def instance
      CuratorSetting.instance
    end

    private

    def present(value)
      text = value.to_s.strip
      text.empty? ? nil : text
    end
  end
end
