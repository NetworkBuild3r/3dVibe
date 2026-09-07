# frozen_string_literal: true

require "base64"
require_relative "test_helper"

class VisionTest < Minitest::Test
  include CuratorTestHelper

  def llm_payload
    JSON.generate({
      "proposals" => [
        {
          "kind" => "tag",
          "summary" => "Tag Alpha One as brass horn",
          "rationale" => "cover shows a brass signal horn",
          "payload" => { "model_id" => 12, "folder_name" => "alpha-one", "tag" => "horn", "tags" => ["horn"] }
        }
      ]
    })
  end

  def test_catalog_keeps_ready_cover_urls_and_omits_others
    payload = sample_catalog
    payload["models"][0]["cover_url"] = "/covers/12.webp"
    payload["models"][0]["cover_lqip_url"] = "/covers/12.lqip.webp"
    payload["models"][1]["cover_status"] = "pending"
    payload["models"][1]["cover_url"] = "/covers/13.webp"
    payload["models"][1]["cover_lqip_url"] = "/covers/13.lqip.webp"

    catalog = VibeCurator::Catalog.normalize(payload)
    ready = catalog["models"].find { |row| row["id"] == 12 }
    pending = catalog["models"].find { |row| row["id"] == 13 }

    assert_equal "/covers/12.webp", ready["cover_url"]
    assert_equal "/covers/12.lqip.webp", ready["cover_lqip_url"]
    refute pending.key?("cover_url")
    refute pending.key?("cover_lqip_url")
  end

  def test_catalog_rejects_mesh_paths_as_cover_urls
    payload = sample_catalog
    payload["models"][0]["cover_url"] = "alpha-one/horn.stl"
    payload["models"][0]["cover_lqip_url"] = "/library/alpha-one/horn.stl"

    catalog = VibeCurator::Catalog.normalize(payload)
    ready = catalog["models"].find { |row| row["id"] == 12 }
    refute ready.key?("cover_url")
    refute ready.key?("cover_lqip_url")
  end

  def test_pick_cover_prefers_lqip_then_cover
    catalog = catalog_with_ready_cover
    pick = VibeCurator::Vision.pick_cover(catalog)
    assert_equal "cover_lqip_url", pick[:source]
    assert_equal "/covers/12.lqip.webp", pick[:url]
    assert_equal 12, pick[:model_id]

    catalog["models"][0].delete("cover_lqip_url")
    pick = VibeCurator::Vision.pick_cover(catalog)
    assert_equal "cover_url", pick[:source]
    assert_equal "/covers/12.webp", pick[:url]
  end

  def test_pick_cover_skips_missing_pending_failed
    catalog = sample_catalog
    catalog["models"][0]["cover_status"] = "failed"
    catalog["models"][0]["cover_url"] = "/covers/12.webp"
    assert_nil VibeCurator::Vision.pick_cover(catalog)

    catalog["models"][0]["cover_status"] = "missing"
    assert_nil VibeCurator::Vision.pick_cover(catalog)
  end

  def test_xai_attaches_one_fixture_image_as_data_url
    Dir.mktmpdir do |root|
      seen = nil
      transport = fake_openai_transport(llm_payload) do |_uri, request|
        seen = JSON.parse(request.body)
      end
      env = cover_root_env(root, "VIBE_CURATOR_PROVIDER" => "xai", "XAI_API_KEY" => "xai-test-key")
      result = VibeCurator::Service.proposals(payload: catalog_with_ready_cover, env: env, transport: transport)

      assert_equal "xai", result["provider"]
      assert_equal 1, result["proposals"].size
      user = seen["messages"][1]
      assert user["content"].is_a?(Array)
      assert_equal 2, user["content"].size
      text = user["content"][0]
      image = user["content"][1]
      assert_equal "text", text["type"]
      payload = JSON.parse(text["text"])
      assert_equal 12, payload.dig("cover_image", "model_id")
      assert_equal "cover_lqip_url", payload.dig("cover_image", "source")
      assert_equal "image_url", image["type"]
      url = image.dig("image_url", "url").to_s
      assert url.start_with?("data:image/png;base64,")
      decoded = Base64.decode64(url.split(",", 2).last).b
      assert_equal File.binread(FIXTURE_COVER), decoded
    end
  end

  def test_ollama_native_attaches_images_and_uses_vision_model
    Dir.mktmpdir do |root|
      seen = nil
      transport = fake_ollama_transport(llm_payload) do |_uri, request|
        seen = JSON.parse(request.body)
      end
      env = cover_root_env(root,
        "VIBE_CURATOR_PROVIDER" => "ollama",
        "VIBE_OLLAMA_URL" => "http://ollama.local:11434",
        "VIBE_OLLAMA_MODEL" => "llama3.1",
        "VIBE_OLLAMA_VISION_MODEL" => "llava"
      )
      VibeCurator::Service.proposals(payload: catalog_with_ready_cover, env: env, transport: transport)

      assert_equal "llava", seen["model"]
      user = seen["messages"][1]
      assert user["content"].is_a?(String)
      assert JSON.parse(user["content"])["cover_image"]
      assert_equal [Base64.strict_encode64(File.binread(FIXTURE_COVER))], user["images"]
    end
  end

  def test_ollama_openai_attaches_image_url_parts
    Dir.mktmpdir do |root|
      seen = nil
      transport = fake_openai_transport(llm_payload) do |_uri, request|
        seen = JSON.parse(request.body)
      end
      env = cover_root_env(root,
        "VIBE_CURATOR_PROVIDER" => "ollama",
        "VIBE_OLLAMA_URL" => "http://ollama.local:11434/v1",
        "VIBE_OLLAMA_API" => "openai"
      )
      VibeCurator::Service.proposals(payload: catalog_with_ready_cover, env: env, transport: transport)
      user = seen["messages"][1]
      assert user["content"].is_a?(Array)
      assert_equal "image_url", user["content"][1]["type"]
    end
  end

  def test_live_path_is_text_only_when_cover_missing
    seen = nil
    transport = fake_openai_transport(llm_payload) do |_uri, request|
      seen = JSON.parse(request.body)
    end
    env = env_hash("VIBE_CURATOR_PROVIDER" => "xai", "XAI_API_KEY" => "xai-test-key")
    VibeCurator::Service.proposals(payload: sample_catalog, env: env, transport: transport)

    user = seen["messages"][1]
    assert_equal "user", user["role"]
    assert user["content"].is_a?(String)
    payload = JSON.parse(user["content"])
    refute payload.key?("cover_image")
    refute user.key?("images")
  end

  def test_failed_fetch_falls_back_to_text_only
    seen = nil
    fetch = lambda { |_url, _env| nil }
    transport = fake_openai_transport(llm_payload) do |_uri, request|
      seen = JSON.parse(request.body)
    end
    catalog = catalog_with_ready_cover
    env = env_hash(
      "VIBE_CURATOR_PROVIDER" => "xai",
      "XAI_API_KEY" => "xai-test-key",
      "VIBE_COVER_BASE_URL" => "http://api.test"
    )
    VibeCurator::Service.proposals(payload: catalog, env: env, transport: transport, fetch: fetch)
    assert seen["messages"][1]["content"].is_a?(String)
  end

  def test_over_budget_bytes_are_skipped
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(root)
      File.binwrite(File.join(root, "12.lqip.webp"), File.binread(FIXTURE_COVER) + ("\x00" * 2000))
      seen = nil
      transport = fake_openai_transport(llm_payload) do |_uri, request|
        seen = JSON.parse(request.body)
      end
      env = env_hash(
        "VIBE_CURATOR_PROVIDER" => "xai",
        "XAI_API_KEY" => "xai-test-key",
        "VIBE_COVER_ROOT" => root,
        "VIBE_CURATOR_VISION_MAX_BYTES" => "256"
      )
      VibeCurator::Service.proposals(payload: catalog_with_ready_cover, env: env, transport: transport)
      assert seen["messages"][1]["content"].is_a?(String)
    end
  end

  def test_over_budget_pixels_are_skipped
    Dir.mktmpdir do |root|
      huge = oversized_png(width: 2048, height: 2048)
      File.binwrite(File.join(root, "12.lqip.webp"), huge)
      seen = nil
      transport = fake_openai_transport(llm_payload) do |_uri, request|
        seen = JSON.parse(request.body)
      end
      env = env_hash(
        "VIBE_CURATOR_PROVIDER" => "xai",
        "XAI_API_KEY" => "xai-test-key",
        "VIBE_COVER_ROOT" => root,
        "VIBE_CURATOR_VISION_MAX_PX" => "32"
      )
      VibeCurator::Service.proposals(payload: catalog_with_ready_cover, env: env, transport: transport)
      assert seen["messages"][1]["content"].is_a?(String)
    end
  end

  def test_http_cover_fetch_uses_base_url
    seen = nil
    fetched = nil
    fetch = lambda do |url, _env|
      fetched = url
      File.binread(FIXTURE_COVER)
    end
    transport = fake_openai_transport(llm_payload) do |_uri, request|
      seen = JSON.parse(request.body)
    end
    env = env_hash(
      "VIBE_CURATOR_PROVIDER" => "xai",
      "XAI_API_KEY" => "xai-test-key",
      "VIBE_COVER_BASE_URL" => "http://api:3000"
    )
    VibeCurator::Service.proposals(payload: catalog_with_ready_cover, env: env, transport: transport, fetch: fetch)
    assert_equal "http://api:3000/covers/12.lqip.webp", fetched
    assert seen["messages"][1]["content"].is_a?(Array)
  end

  def test_stub_never_loads_or_attaches_vision
    Dir.mktmpdir do |root|
      env = cover_root_env(root)
      reads = 0
      fetch = lambda do |_url, _env|
        reads += 1
        raise "stub must not fetch covers"
      end
      result = VibeCurator::Service.proposals(
        payload: catalog_with_ready_cover,
        env: env,
        fetch: fetch
      )
      assert_equal "stub", result["provider"]
      assert_equal 0, reads
      kinds = result["proposals"].map { |item| item["kind"] }
      assert_includes kinds, "tag"
      assert_includes kinds, "rename"
      dumped = JSON.generate(result)
      refute_includes dumped, "data:image"
      refute_includes dumped, Base64.strict_encode64(File.binread(FIXTURE_COVER))
    end
  end

  def test_system_prompt_teaches_cover_vision
    text = VibeCurator::Prompt.system_prompt(budget: 8)
    assert_includes text, "Cover image"
    assert_includes text, "Prefer what you see"
    assert_includes text, "cover_lqip_url"
  end

  private

  def oversized_png(width:, height:)
    fixture = File.binread(FIXTURE_COVER)
    # Rewrite IHDR width/height only. The px reader does not check CRC.
    out = fixture.dup
    out[16, 8] = [width, height].pack("NN")
    out
  end
end
