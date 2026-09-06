# frozen_string_literal: true

require_relative "catalog"
require_relative "chat_client"
require_relative "config"
require_relative "prompt"
require_relative "stub_proposals"

module VibeCurator
  module Providers
    module_function

    def build(name, env: ENV, transport: nil)
      case name.to_s
      when "ollama" then Ollama.new(env: env, transport: transport)
      when "xai" then Xai.new(env: env, transport: transport)
      else Stub.new
      end
    end

    class Stub
      def name
        "stub"
      end

      def propose(catalog)
        CuratorStub.proposals_for(catalog["models"])
      end
    end

    class ChatProvider
      def propose(catalog)
        ranked = Catalog.rank_for_inference(catalog["models"], limit: Config.catalog_limit(env: @env))
        prompt_catalog = catalog.merge("models" => ranked)
        content = client.complete(
          model: model,
          messages: [
            { "role" => "system", "content" => Prompt.system_prompt(budget: Config.batch_size(env: @env)) },
            { "role" => "user", "content" => Prompt.user_prompt(prompt_catalog) }
          ],
          extra: extra_body
        )
        parsed = ChatClient.parse_json_content(content)
        items = parsed.is_a?(Hash) ? (parsed["proposals"] || parsed["drafts"] || []) : []
        Array(items)
      end

      private

      def extra_body
        {}
      end
    end

    class Ollama < ChatProvider
      def initialize(env: ENV, transport: nil)
        @env = env
        @transport = transport
      end

      def name
        "ollama"
      end

      private

      def client
        ChatClient.new(
          base_url: base_url,
          path: native? ? "/api/chat" : "/chat/completions",
          api_key: @env["VIBE_OLLAMA_API_KEY"].to_s,
          timeout: Config.infer_timeout(env: @env),
          transport: @transport
        )
      end

      def model
        Config.present(@env["VIBE_OLLAMA_MODEL"]) || "llama3.1"
      end

      def extra_body
        native? ? { "stream" => false, "format" => "json" } : { "temperature" => 0.2 }
      end

      def native?
        api = @env["VIBE_OLLAMA_API"].to_s.strip.downcase
        return false if api == "openai"
        return true if api == "native" || api == "ollama"

        !base_url.end_with?("/v1")
      end

      def base_url
        raw = @env["VIBE_OLLAMA_URL"].to_s.strip
        raw = "http://127.0.0.1:11434" if raw.empty?
        raw.chomp("/")
      end
    end

    class Xai < ChatProvider
      def initialize(env: ENV, transport: nil)
        @env = env
        @transport = transport
      end

      def name
        "xai"
      end

      def propose(catalog)
        raise Error.new("XAI_API_KEY is blank", status: 503, code: "xai_not_configured") if api_key.empty?

        super
      end

      private

      def client
        ChatClient.new(
          base_url: base_url,
          path: "/chat/completions",
          api_key: api_key,
          timeout: Config.infer_timeout(env: @env),
          transport: @transport
        )
      end

      def model
        Config.present(@env["XAI_MODEL"]) || Config.present(@env["VIBE_XAI_MODEL"]) || "grok-4"
      end

      def extra_body
        { "temperature" => 0.2 }
      end

      def api_key
        Config.present(@env["XAI_API_KEY"]) || Config.present(@env["VIBE_XAI_API_KEY"]) || ""
      end

      def base_url
        (Config.present(@env["XAI_BASE_URL"]) || Config.present(@env["VIBE_XAI_BASE_URL"]) || "https://api.x.ai/v1").chomp("/")
      end
    end
  end
end
