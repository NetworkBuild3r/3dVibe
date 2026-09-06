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

  def sample_catalog
    JSON.parse(JSON.generate(SAMPLE_CATALOG))
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
