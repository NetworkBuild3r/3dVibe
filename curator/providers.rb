# frozen_string_literal: true

require_relative "catalog"
require_relative "chat_client"
require_relative "config"
require_relative "prompt"
require_relative "stub_proposals"
require_relative "vision"

module VibeCurator
  module Providers
    module_function

    def build(name, env: ENV, transport: nil, fetch: nil)
      case name.to_s
      when "stub" then Stub.new
      when "ollama" then Ollama.new(env: env, transport: transport, fetch: fetch)
      when "xai" then OpenAICompat.new("xai", env: env, transport: transport, fetch: fetch)
      when "openai" then OpenAICompat.new("openai", env: env, transport: transport, fetch: fetch)
      when "anthropic" then Anthropic.new(env: env, transport: transport, fetch: fetch)
      else
        raise Error.new(
          "unknown curator provider #{name.inspect}; expected stub|ollama|xai|openai|anthropic",
          status: 503,
          code: "unknown_provider"
        )
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
      attr_reader :vision_skip_reason

      def propose(catalog)
        @vision_skip_reason = nil
        ranked = Catalog.rank_for_inference(catalog["models"], limit: Config.catalog_limit(env: @env))
        prompt_catalog = catalog.merge("models" => ranked)
        vision = Vision.attach_result(prompt_catalog, env: @env, fetch: @fetch)
        @vision_skip_reason = vision.skip_reason
        cover = vision.attachment
        content = client.complete(
          model: model_for(cover),
          messages: chat_messages(prompt_catalog, cover),
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

      def model_for(_cover)
        model
      end

      def native_images?
        false
      end

      def image_style
        native_images? ? :native : :openai
      end

      def system_prompt
        Prompt.system_prompt(
          budget: Config.batch_size(env: @env),
          max_per_kind: Config.max_per_kind(env: @env),
          kind_priority: Config.kind_priority(env: @env),
          min_confidence: Config.min_confidence(env: @env)
        )
      end

      def chat_messages(catalog, cover)
        [
          { "role" => "system", "content" => system_prompt },
          Prompt.user_chat_message(catalog, cover: cover, image_style: image_style)
        ]
      end
    end

    class Ollama < ChatProvider
      def initialize(env: ENV, transport: nil, fetch: nil)
        @env = env
        @transport = transport
        @fetch = fetch
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
        Config.present(@env["VIBE_OLLAMA_MODEL"]) || "gemma4"
      end

      def extra_body
        native? ? { "stream" => false, "format" => "json" } : { "temperature" => 0.2 }
      end

      def model_for(cover)
        if cover && (vision = Config.present(@env["VIBE_OLLAMA_VISION_MODEL"]))
          vision
        else
          model
        end
      end

      def native_images?
        native?
      end

      def native?
        api = @env["VIBE_OLLAMA_API"].to_s.strip.downcase
        return false if api == "openai"
        return true if api == "native" || api == "ollama"

        !base_url.end_with?("/v1")
      end

      def base_url
        Config.require_ollama_url!(@env["VIBE_OLLAMA_URL"]).chomp("/")
      end
    end

    class OpenAICompat < ChatProvider
      SPECS = {
        "xai" => {
          key: %w[XAI_API_KEY VIBE_XAI_API_KEY],
          model: %w[XAI_MODEL VIBE_XAI_MODEL],
          base_url: %w[XAI_BASE_URL VIBE_XAI_BASE_URL],
          default_model: "grok-4",
          default_base_url: "https://api.x.ai/v1",
          missing: "XAI_API_KEY is blank",
          code: "xai_not_configured"
        },
        "openai" => {
          key: %w[OPENAI_API_KEY VIBE_OPENAI_API_KEY],
          model: %w[OPENAI_MODEL VIBE_OPENAI_MODEL],
          base_url: %w[OPENAI_BASE_URL VIBE_OPENAI_BASE_URL],
          default_model: "gpt-4o",
          default_base_url: "https://api.openai.com/v1",
          missing: "OPENAI_API_KEY is blank",
          code: "openai_not_configured"
        }
      }.freeze

      def initialize(name, env: ENV, transport: nil, fetch: nil)
        @name = name.to_s
        @spec = SPECS.fetch(@name)
        @env = env
        @transport = transport
        @fetch = fetch
      end

      def name
        @name
      end

      def propose(catalog)
        raise Error.new(@spec[:missing], status: 503, code: @spec[:code]) if api_key.empty?

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
        first_present(@spec[:model]) || @spec[:default_model]
      end

      def extra_body
        { "temperature" => 0.2 }
      end

      def api_key
        first_present(@spec[:key]) || ""
      end

      def base_url
        (first_present(@spec[:base_url]) || @spec[:default_base_url]).chomp("/")
      end

      def first_present(keys)
        keys.each do |key|
          value = Config.present(@env[key])
          return value if value
        end
        nil
      end
    end

    class Anthropic < ChatProvider
      def initialize(env: ENV, transport: nil, fetch: nil)
        @env = env
        @transport = transport
        @fetch = fetch
      end

      def name
        "anthropic"
      end

      def propose(catalog)
        raise Error.new("ANTHROPIC_API_KEY is blank", status: 503, code: "anthropic_not_configured") if api_key.empty?

        super
      end

      private

      def client
        ChatClient.new(
          base_url: base_url,
          path: messages_path,
          api_key: api_key,
          bearer: false,
          timeout: Config.infer_timeout(env: @env),
          transport: @transport,
          headers: {
            "x-api-key" => api_key,
            "anthropic-version" => "2023-06-01"
          }
        )
      end

      def model
        Config.present(@env["ANTHROPIC_MODEL"]) || Config.present(@env["VIBE_ANTHROPIC_MODEL"]) || "claude-sonnet-4-5"
      end

      def extra_body
        { "max_tokens" => 4096, "temperature" => 0.2, "system" => system_prompt }
      end

      def image_style
        :anthropic
      end

      def chat_messages(catalog, cover)
        [Prompt.user_chat_message(catalog, cover: cover, image_style: image_style)]
      end

      def api_key
        Config.present(@env["ANTHROPIC_API_KEY"]) || Config.present(@env["VIBE_ANTHROPIC_API_KEY"]) || ""
      end

      def base_url
        raw = Config.present(@env["ANTHROPIC_BASE_URL"]) || Config.present(@env["VIBE_ANTHROPIC_BASE_URL"]) || "https://api.anthropic.com"
        raw.to_s.chomp("/")
      end

      def messages_path
        base_url.end_with?("/v1") ? "/messages" : "/v1/messages"
      end
    end
  end
end
