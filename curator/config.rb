# frozen_string_literal: true

# Env-selected curator settings. Rails still chooses the sidecar with
# VIBE_CURATOR_URL=stub|http://curator:8088; this process only reads
# VIBE_CURATOR_PROVIDER (and an optional catalog provider_hint).
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
      env_name = normalize_provider(env["VIBE_CURATOR_PROVIDER"])
      return env_name if env_name

      hint = catalog.is_a?(Hash) ? catalog["provider_hint"] : nil
      normalize_provider(hint) || "stub"
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
