# frozen_string_literal: true

# Dev stub curator. Emits deterministic rename/move/tag/merge proposals.
# Point a real Spark curator at the same HTTP contract later.
require "json"
require "webrick"
require_relative "stub_proposals"

PORT = Integer(ENV.fetch("PORT", "8088"))
TOKEN = ENV["VIBE_CURATOR_TOKEN"].to_s
LIBRARY_ROOT = ENV.fetch("LIBRARY_ROOT", "/library")

def authorized?(request)
  return true if TOKEN.empty?

  bearer = request["Authorization"].to_s.split(" ", 2).last
  presented = request["X-Curator-Token"].to_s
  presented = bearer if presented.empty?
  presented == TOKEN
end

def json(response, status, body)
  response.status = status
  response["Content-Type"] = "application/json"
  response.body = JSON.generate(body)
end

def read_json(request)
  raw = request.body
  return {} if raw.nil?

  data = raw.read
  return {} if data.nil? || data.empty?

  JSON.parse(data)
rescue JSON::ParserError
  {}
end

def catalog_models(request, payload)
  models = payload["models"]
  return models if models.is_a?(Array) && models.any?

  root = payload["library_root"].to_s
  root = request.query["library_root"] if root.empty?
  root = LIBRARY_ROOT if root.empty?
  CuratorStub.models_from_library_root(root)
end

server = WEBrick::HTTPServer.new(Port: PORT, BindAddress: "0.0.0.0", Logger: WEBrick::Log.new($stdout, WEBrick::Log::INFO))

server.mount_proc "/health" do |_request, response|
  json(response, 200, { "ok" => true, "service" => "3dvibe-curator-stub" })
end

server.mount_proc "/proposals" do |request, response|
  unless authorized?(request)
    json(response, 401, { "error" => "unauthorized" })
    next
  end

  unless %w[GET POST].include?(request.request_method)
    json(response, 405, { "error" => "method_not_allowed" })
    next
  end

  payload = request.request_method == "POST" ? read_json(request) : {}
  models = catalog_models(request, payload)
  provider = payload["provider_hint"].to_s
  provider = request.query["provider_hint"].to_s if provider.empty?
  provider = "stub" if provider.empty?
  response["X-Curator-Provider"] = provider
  json(response, 200, { "proposals" => CuratorStub.proposals_for(models), "provider" => provider })
end

server.mount_proc "/" do |_request, response|
  json(response, 200, {
    "service" => "3dvibe-curator-stub",
    "contract" => {
      "POST /proposals" => "preferred; send catalog snapshot { library_id, library_root, provider_hint, creators_index, models[] }",
      "GET /proposals" => "fallback; lists LIBRARY_ROOT first-level folders",
      "auth" => "Bearer VIBE_CURATOR_TOKEN or X-Curator-Token"
    }
  })
end

%w[INT TERM].each { |signal| trap(signal) { server.shutdown } }
server.start
