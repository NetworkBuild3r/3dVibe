# frozen_string_literal: true

require "json"
require_relative "catalog"
require_relative "config"
require_relative "proposal_batch"
require_relative "providers"

module VibeCurator
  # HTTP contract for Rails CurationSidecar / CurationHttpClient.
  module Service
    module_function

    def health(env: ENV)
      provider = Config.provider_name({}, env: env)
      {
        "ok" => true,
        "service" => service_name(provider),
        "provider" => provider
      }
    end

    def index(env: ENV)
      provider = Config.provider_name({}, env: env)
      {
        "service" => service_name(provider),
        "provider" => provider,
        "contract" => {
          "POST /proposals" => "preferred; send catalog snapshot { library_id, library_root, provider_hint, curator_runtime, creators_index, models[] }",
          "GET /proposals" => "fallback; lists LIBRARY_ROOT first-level folders (no secrets on the query string)",
          "auth" => "Bearer VIBE_CURATOR_TOKEN or X-Curator-Token",
          "providers" => "curator_runtime.provider → VIBE_CURATOR_PROVIDER=stub|ollama|xai → provider_hint"
        }
      }
    end

    def proposals(payload:, query: {}, env: ENV, transport: nil)
      catalog = Catalog.normalize(payload, query: query, env: env)
      env = Config.env_with_runtime(catalog, env)
      provider_name = Config.provider_name(catalog, env: env)
      catalog = catalog.except("curator_runtime")
      provider = Providers.build(provider_name, env: env, transport: transport)
      raw = provider.propose(catalog)
      items = ProposalBatch.normalize(
        raw,
        catalog: catalog,
        provider: provider.name,
        budget: Config.batch_size(env: env)
      )
      {
        "provider" => provider.name,
        "proposals" => items
      }
    end

    def authorized?(headers, env: ENV)
      expected = Config.token(env: env)
      return true if expected.empty?

      presented = headers["X-Curator-Token"].to_s
      presented = headers["x-curator-token"].to_s if presented.empty?
      if presented.empty?
        auth = headers["Authorization"].to_s
        auth = headers["authorization"].to_s if auth.empty?
        presented = auth.split(" ", 2).last.to_s
      end
      presented == expected
    end

    def service_name(provider)
      provider.to_s == "stub" ? "3dvibe-curator-stub" : "3dvibe-curator"
    end
  end

  module HTTP
    module_function

    def handle(method:, path:, headers: {}, body: "", query: {}, env: ENV, transport: nil)
      method = method.to_s.upcase
      path = path.to_s.split("?").first
      path = "/" if path.empty?

      case path
      when "/health"
        ok(Service.health(env: env))
      when "/"
        ok(Service.index(env: env))
      when "/proposals"
        proposals(method, headers, body, query, env, transport)
      else
        error(404, "not_found")
      end
    rescue Error => e
      error(e.status, e.code, e.message)
    end

    def proposals(method, headers, body, query, env, transport)
      return error(401, "unauthorized") unless Service.authorized?(headers, env: env)
      return error(405, "method_not_allowed") unless %w[GET POST].include?(method)

      payload = method == "POST" ? parse_json(body) : {}
      result = Service.proposals(payload: payload, query: query, env: env, transport: transport)
      ok(result, headers: { "X-Curator-Provider" => result["provider"] })
    end

    def parse_json(body)
      text = body.to_s
      return {} if text.empty?

      JSON.parse(text)
    rescue JSON::ParserError
      {}
    end

    def ok(body, headers: {})
      { status: 200, headers: { "Content-Type" => "application/json" }.merge(headers), body: body }
    end

    def error(status, code, message = nil)
      payload = { "error" => code }
      payload["message"] = message if message
      { status: status, headers: { "Content-Type" => "application/json" }, body: payload }
    end
  end
end
