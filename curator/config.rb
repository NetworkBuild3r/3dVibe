# frozen_string_literal: true

# Sidecar settings. Rails still chooses the process with VIBE_CURATOR_URL
# (stub | http://curator:8088). Adapter resolution is request-scoped:
#
#   curator_runtime (Rails POST /proposals) field → process ENV →
#   catalog provider_hint → stub
#
# Incomplete runtime falls back field-by-field. Process ENV is never mutated.
# Stub never requires a key; secrets are dropped from the request-scoped env.
# Rails sends only the decrypted key for the active provider (xai / openai /
# anthropic). Compose/CI stay on stub. Owner UI default is ollama + gemma4.
module VibeCurator
  KINDS = %w[tag rename move merge organize].freeze
  PROVIDERS = %w[stub ollama xai openai anthropic].freeze
  DEFAULT_BATCH_SIZE = 8
  MAX_BATCH_SIZE = 50
  DEFAULT_CATALOG_LIMIT = 80
  DEFAULT_INFER_TIMEOUT = 60
  DEFAULT_MAX_PER_KIND = 3
  DEFAULT_KIND_PRIORITY = %w[merge organize tag rename move].freeze
  DEFAULT_VISION_MAX_BYTES = 250_000
  DEFAULT_VISION_MAX_PX = 512
  DEFAULT_VISION_TIMEOUT = 3
  # Shape injected by Rails CuratorRuntime.for_sidecar (PR #23). GET /proposals
  # must not carry these on the query string.
  RUNTIME_FIELDS = %w[
    provider ollama_url ollama_model
    xai_api_key openai_api_key anthropic_api_key
  ].freeze
  SECRET_ENV_KEYS = %w[
    XAI_API_KEY VIBE_XAI_API_KEY
    OPENAI_API_KEY VIBE_OPENAI_API_KEY
    ANTHROPIC_API_KEY VIBE_ANTHROPIC_API_KEY
    VIBE_OLLAMA_API_KEY
  ].freeze

  module Config
    module_function

    def resolve(catalog = {}, env: ENV)
      scoped = env_with_runtime(catalog, env)
      name = provider_name(catalog, env: scoped)
      scoped = strip_secrets(scoped) if name == "stub"
      [name, scoped]
    end

    def provider_name(catalog = {}, env: ENV)
      runtime = runtime_from(catalog)
      runtime_name = normalize_provider(runtime["provider"])
      return runtime_name if runtime_name

      env_name = normalize_provider(env["VIBE_CURATOR_PROVIDER"])
      return env_name if env_name

      hint = catalog.is_a?(Hash) ? catalog["provider_hint"] : nil
      normalize_provider(hint) || "stub"
    end

    # Overlay owner UI runtime onto a copy of sidecar ENV. Secrets stay
    # request-scoped. Blank / null runtime fields leave the env value in place.
    def env_with_runtime(catalog, env)
      merged = stringify_env(env)
      runtime = runtime_from(catalog)
      return merged if runtime.empty?

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
      if (key = present(runtime["openai_api_key"]))
        merged["OPENAI_API_KEY"] = key
      end
      if (key = present(runtime["anthropic_api_key"]))
        merged["ANTHROPIC_API_KEY"] = key
      end
      merged
    end

    def runtime_from(catalog)
      return {} unless catalog.is_a?(Hash)

      runtime = catalog["curator_runtime"] || catalog[:curator_runtime]
      runtime.is_a?(Hash) ? runtime.transform_keys(&:to_s) : {}
    end

    def scrub_catalog(catalog)
      return {} unless catalog.is_a?(Hash)

      catalog.transform_keys(&:to_s).except("curator_runtime")
    end

    def strip_secrets(env)
      stringify_env(env).except(*SECRET_ENV_KEYS)
    end

    def redact(text, env)
      secrets = SECRET_ENV_KEYS.filter_map { |key| present(env[key]) }
      secrets.reduce(text.to_s) { |acc, secret| acc.gsub(secret, "[filtered]") }
    end

    def stringify_env(env)
      env.to_h.transform_keys(&:to_s)
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

    # Live batch only. Stub ignores this so CI fixtures stay byte-stable.
    def max_per_kind(env: ENV)
      clamp_int(env["VIBE_CURATOR_MAX_PER_KIND"], default: DEFAULT_MAX_PER_KIND, min: 1, max: MAX_BATCH_SIZE)
    end

    def kind_priority(env: ENV)
      names = env["VIBE_CURATOR_KIND_PRIORITY"].to_s.split(/[,\s]+/).map { |name| name.strip.downcase }
      names = names.select { |name| KINDS.include?(name) }.uniq
      names.empty? ? DEFAULT_KIND_PRIORITY.dup : names
    end

    # Drop live proposals below this score only when the provider returned confidence.
    # 0 (default) means "do not filter on confidence".
    def min_confidence(env: ENV)
      raw = env["VIBE_CURATOR_MIN_CONFIDENCE"].to_s.strip
      return 0.0 if raw.empty?

      value = Float(raw)
      return 0.0 unless value.finite?

      [[value, 0.0].max, 1.0].min
    rescue ArgumentError, TypeError
      0.0
    end

    def library_root(env: ENV)
      env.fetch("LIBRARY_ROOT", "/library")
    end

    # Live vision only. Stub never loads covers. Caps match Rails cover budgets.
    def vision_max_bytes(env: ENV)
      clamp_int(env["VIBE_CURATOR_VISION_MAX_BYTES"], default: DEFAULT_VISION_MAX_BYTES, min: 256, max: 2_000_000)
    end

    def vision_max_px(env: ENV)
      clamp_int(env["VIBE_CURATOR_VISION_MAX_PX"], default: DEFAULT_VISION_MAX_PX, min: 16, max: 2048)
    end

    def vision_timeout(env: ENV)
      clamp_int(env["VIBE_CURATOR_VISION_TIMEOUT"], default: DEFAULT_VISION_TIMEOUT, min: 1, max: 30)
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
