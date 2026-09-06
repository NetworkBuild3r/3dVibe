# frozen_string_literal: true

# Env-selected curator settings. Rails still chooses the sidecar with
# VIBE_CURATOR_URL=stub|http://curator:8088. Provider resolution:
# catalog curator_runtime (owner UI) → VIBE_CURATOR_PROVIDER → provider_hint → stub.
module VibeCurator
  KINDS = %w[tag rename move merge organize].freeze
  PROVIDERS = %w[stub ollama xai].freeze
  DEFAULT_BATCH_SIZE = 8
  MAX_BATCH_SIZE = 50
  DEFAULT_CATALOG_LIMIT = 80
  DEFAULT_INFER_TIMEOUT = 60

  module Config
    module_function

    def provider_name(catalog = {}, env: ENV)
      runtime = runtime_from(catalog)
      runtime_name = normalize_provider(runtime["provider"])
      return runtime_name if runtime_name

      env_name = normalize_provider(env["VIBE_CURATOR_PROVIDER"])
      return env_name if env_name

      hint = catalog.is_a?(Hash) ? catalog["provider_hint"] : nil
      normalize_provider(hint) || "stub"
    end

    # Overlay owner UI runtime onto sidecar ENV. Secrets stay request-scoped.
    def env_with_runtime(catalog, env)
      runtime = runtime_from(catalog)
      return env if runtime.empty?

      merged = env.to_h.transform_keys(&:to_s)
      if (name = present(runtime["provider"]))
        merged["VIBE_CURATOR_PROVIDER"] = name
      end
      if (url = present(runtime["ollama_url"]))
        merged["VIBE_OLLAMA_URL"] = url
      end
      if (model = present(runtime["ollama_model"]))
        merged["VIBE_OLLAMA_MODEL"] = model
      end
      if (key = present(runtime["xai_api_key"]))
        merged["XAI_API_KEY"] = key
      end
      merged
    end

    def runtime_from(catalog)
      return {} unless catalog.is_a?(Hash)

      runtime = catalog["curator_runtime"]
      runtime.is_a?(Hash) ? runtime.transform_keys(&:to_s) : {}
    end

    def batch_size(env: ENV)
      clamp_int(env["VIBE_CURATOR_BATCH_SIZE"], default: DEFAULT_BATCH_SIZE, min: 1, max: MAX_BATCH_SIZE)
    end

    def catalog_limit(env: ENV)
      clamp_int(env["VIBE_CURATOR_CATALOG_LIMIT"], default: DEFAULT_CATALOG_LIMIT, min: 1, max: 500)
    end

    def infer_timeout(env: ENV)
      clamp_int(env["VIBE_CURATOR_INFER_TIMEOUT"], default: DEFAULT_INFER_TIMEOUT, min: 1, max: 600)
    end

    def library_root(env: ENV)
      env.fetch("LIBRARY_ROOT", "/library")
    end

    def token(env: ENV)
      env["VIBE_CURATOR_TOKEN"].to_s
    end

    def normalize_provider(value)
      name = value.to_s.strip.downcase
      return if name.empty?
      return "stub" if %w[stub stub://local internal].include?(name)

      name
    end

    def present(value)
      text = value.to_s.strip
      text.empty? ? nil : text
    end

    def clamp_int(value, default:, min:, max:)
      parsed = Integer(value.to_s)
      [[parsed, min].max, max].min
    rescue ArgumentError, TypeError
      default
    end
  end

  class Error < StandardError
    attr_reader :status, :code

    def initialize(message, status: 502, code: "provider_error")
      super(message)
      @status = status
      @code = code
    end
  end
end
