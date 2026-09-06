# frozen_string_literal: true

require "json"
require "net/http"
require "uri"
require_relative "config"

module VibeCurator
  # Minimal OpenAI-compatible / Ollama chat client. Transport is injectable
  # so tests can mock provider responses without a network.
  class ChatClient
    def initialize(base_url:, path:, api_key: nil, timeout: 60, transport: nil, headers: {})
      @base_url = base_url.to_s.chomp("/")
      @path = path.start_with?("/") ? path : "/#{path}"
      @api_key = api_key.to_s
      @timeout = timeout.to_f
      @transport = transport
      @headers = headers
    end

    def complete(model:, messages:, extra: {})
      body = { "model" => model, "messages" => messages }.merge(extra)
      uri = URI.parse("#{@base_url}#{@path}")
      response = perform(uri, body)
      code = response_code(response)
      raw = response_body(response)
      unless code.between?(200, 299)
        snippet = redact(raw.to_s[0, 240])
        raise Error.new("provider HTTP #{code}: #{snippet}", status: 502, code: "provider_http")
      end

      parsed = JSON.parse(raw.to_s.empty? ? "{}" : raw)
      extract_content(parsed)
    rescue JSON::ParserError => e
      raise Error.new("provider returned invalid JSON: #{e.message}", status: 502, code: "invalid_json")
    rescue Timeout::Error, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError => e
      raise Error.new("provider unreachable: #{e.message}", status: 502, code: "unreachable")
    end

    def self.parse_json_content(content)
      text = content.to_s.strip
      return {} if text.empty?

      JSON.parse(text)
    rescue JSON::ParserError
      fenced = text[/(?:```json|```)\s*(\{.*?\})\s*```/m, 1]
      return JSON.parse(fenced) if fenced

      brace = text[/{.*}/m]
      return JSON.parse(brace) if brace

      {}
    rescue JSON::ParserError
      {}
    end

    private

    def perform(uri, body)
      request = Net::HTTP::Post.new(uri.request_uri)
      request["Content-Type"] = "application/json"
      request["Accept"] = "application/json"
      request["Authorization"] = "Bearer #{@api_key}" unless @api_key.empty?
      @headers.each { |key, value| request[key] = value }
      request.body = JSON.generate(body)
      return @transport.call(uri, request) if @transport

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = @timeout
      http.read_timeout = @timeout
      http.write_timeout = @timeout if http.respond_to?(:write_timeout=)
      http.request(request)
    end

    def response_code(response)
      if response.respond_to?(:code)
        response.code.to_i
      elsif response.is_a?(Hash)
        response[:code].to_i
      else
        0
      end
    end

    def response_body(response)
      if response.respond_to?(:body)
        response.body
      elsif response.is_a?(Hash)
        response[:body]
      else
        ""
      end
    end

    def redact(text)
      return text.to_s if @api_key.empty?

      text.to_s.gsub(@api_key, "[filtered]")
    end

    def extract_content(parsed)
      if parsed.is_a?(Hash)
        choices = parsed["choices"]
        if choices.is_a?(Array) && choices.first.is_a?(Hash)
          message = choices.first["message"] || {}
          return message["content"].to_s
        end
        message = parsed["message"]
        return message["content"].to_s if message.is_a?(Hash)
        return parsed["response"].to_s if parsed["response"]
        return parsed["output_text"].to_s if parsed["output_text"]
      end
      ""
    end
  end
end
