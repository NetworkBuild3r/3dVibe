# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "tmpdir"
require "fileutils"

$LOAD_PATH.unshift File.expand_path("..", __dir__)

require "service"

module CuratorTestHelper
  SAMPLE_CATALOG = {
    "library_id" => 1,
    "library_name" => "Studio library",
    "library_root" => "/library",
    "provider_hint" => "stub",
    "creators_index" => [
      { "id" => 3, "slug" => "mz4250", "name" => "Mz4250", "model_count" => 12 }
    ],
    "models" => [
      {
        "id" => 12,
        "folder_name" => "alpha-one",
        "title" => "Alpha One",
        "tags" => ["stl"],
        "asset_count" => 2,
        "byte_size" => 1200,
        "creator" => { "id" => 3, "slug" => "mz4250", "name" => "Mz4250" },
        "cover_status" => "ready",
        "mesh_count" => 1,
        "archive_count" => 1,
        "has_archives" => true,
        "sample_paths" => ["alpha-one/horn.stl", "alpha-one/pack.zip"]
      },
      {
        "id" => 13,
        "folder_name" => "beta-two",
        "title" => "Beta Two",
        "tags" => [],
        "asset_count" => 1,
        "byte_size" => 400,
        "creator" => nil,
        "cover_status" => "missing",
        "mesh_count" => 1,
        "archive_count" => 0,
        "has_archives" => false,
        "sample_paths" => ["beta-two/beta.stl"]
      }
    ]
  }.freeze

  FIXTURE_COVER = File.expand_path("fixtures/cover.png", __dir__).freeze

  def sample_catalog
    JSON.parse(JSON.generate(SAMPLE_CATALOG))
  end

  def catalog_with_ready_cover(filename: "12.lqip.webp", include_full: true)
    catalog = sample_catalog
    alpha = catalog["models"].find { |row| row["id"] == 12 }
    alpha["cover_status"] = "ready"
    alpha["cover_lqip_url"] = "/covers/#{filename}" if filename
    alpha["cover_url"] = "/covers/12.webp" if include_full
    catalog
  end

  def cover_root_env(root, overrides = {})
    FileUtils.mkdir_p(root)
    FileUtils.cp(FIXTURE_COVER, File.join(root, "12.lqip.webp"))
    FileUtils.cp(FIXTURE_COVER, File.join(root, "12.webp")) unless File.file?(File.join(root, "12.webp"))
    env_hash({ "VIBE_COVER_ROOT" => root }.merge(overrides))
  end

  def env_hash(overrides = {})
    {
      "VIBE_CURATOR_PROVIDER" => "stub",
      "VIBE_CURATOR_TOKEN" => "secret",
      "VIBE_CURATOR_BATCH_SIZE" => "8",
      "LIBRARY_ROOT" => "/library"
    }.merge(overrides)
  end

  def fake_openai_transport(content, &inspect)
    lambda do |uri, request|
      inspect&.call(uri, request)
      {
        code: 200,
        body: JSON.generate({ "choices" => [{ "message" => { "content" => content } }] })
      }
    end
  end

  def fake_ollama_transport(content, &inspect)
    lambda do |uri, request|
      inspect&.call(uri, request)
      {
        code: 200,
        body: JSON.generate({ "message" => { "content" => content } })
      }
    end
  end
end
