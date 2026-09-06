# frozen_string_literal: true

# Live curator sidecar. Same HTTP contract Rails already polls:
#   GET  /health
#   POST /proposals   catalog snapshot in, proposal batch out
#   GET  /proposals   fallback listing of LIBRARY_ROOT
# Providers: stub (CI default), ollama, xai — VIBE_CURATOR_PROVIDER.
require "json"
require "webrick"
require_relative "service"

PORT = Integer(ENV.fetch("PORT", "8088"))

def webrick_headers(request)
  {
    "Authorization" => request["Authorization"].to_s,
    "X-Curator-Token" => request["X-Curator-Token"].to_s
  }
end

def read_body(request)
  raw = request.body
  return "" if raw.nil?

  data = raw.respond_to?(:read) ? raw.read : raw.to_s
  data.to_s
end

def write_json(response, result)
  response.status = result[:status]
  result[:headers].each { |key, value| response[key] = value }
  response.body = JSON.generate(result[:body])
end

server = WEBrick::HTTPServer.new(
  Port: PORT,
  BindAddress: "0.0.0.0",
  Logger: WEBrick::Log.new($stdout, WEBrick::Log::INFO)
)

server.mount_proc "/" do |request, response|
  result = VibeCurator::HTTP.handle(
    method: request.request_method,
    path: request.path,
    headers: webrick_headers(request),
    body: read_body(request),
    query: request.query || {}
  )
  write_json(response, result)
end

%w[INT TERM].each { |signal| trap(signal) { server.shutdown } }
server.start
