require "test_helper"

class MeilisearchClientTest < ActiveSupport::TestCase
  test "health is unset when MEILI_URL is blank" do
    ENV.delete("MEILI_URL")
    ENV.delete("MEILISEARCH_URL")

    health = MeilisearchClient.new.health
    assert_equal "unset", health[:status]
    refute health[:configured]
    assert_nil health[:last_error]
    refute MeilisearchClient.new.available?
  end

  test "health is down when Meili is configured but unreachable" do
    ENV["MEILI_URL"] = "http://127.0.0.1:9"
    health = MeilisearchClient.new(timeout: 0.2).health
    assert_equal "down", health[:status]
    assert health[:configured]
    assert_match(/meilisearch unreachable|HTTP /, health[:last_error].to_s)
    refute MeilisearchClient.new(timeout: 0.2).available?
  ensure
    ENV.delete("MEILI_URL")
  end
end
