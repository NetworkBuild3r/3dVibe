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
      return CuratorSetting::STUB if value.empty?

      value
    end

    def known_provider?(name = provider)
      PROVIDERS.include?(name.to_s)
    end

    def unknown_provider_message(name = provider)
      "unknown curator provider #{name.inspect}; expected #{PROVIDERS.join('|')}"
    end

    def as_api
      {
        provider: provider,
        ollama_url: ollama_url,
        ollama_model: ollama_model,
        xai_api_key_status: secret_status(CuratorSetting::XAI),
        openai_api_key_status: secret_status(CuratorSetting::OPENAI),
        anthropic_api_key_status: secret_status(CuratorSetting::ANTHROPIC)
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
      present(instance&.public_send(spec[:attribute])) || env_secret(spec)
    end

    def env_secret(spec)
      spec[:env].lazy.map { |name| present(ENV[name]) }.find(&:itself)
    end

    def secret_status(provider_name)
      spec = SECRET_ENV.fetch(provider_name)
      return "set" if present(instance&.public_send(spec[:attribute]))
      return "from_env" if env_secret(spec)

      "missing"
    end

    def present(value)
      text = value.to_s.strip
      text.empty? ? nil : text
    end
  end
end
