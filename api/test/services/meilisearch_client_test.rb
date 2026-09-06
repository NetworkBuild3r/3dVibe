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

  test "health cache reuses one probe within the TTL then refreshes" do
    calls = 0
    probe = lambda do
      calls += 1
      { status: calls == 1 ? "up" : "down", configured: true, last_error: calls == 1 ? nil : "flipped" }
    end

    4.times { MeilisearchClient.fetch_health(ttl: 30, &probe) }
    assert_equal 1, calls
    first = MeilisearchClient.fetch_health(ttl: 30, &probe)
    assert_equal "up", first[:status]

    MeilisearchClient.reset_health_cache!
    second = MeilisearchClient.fetch_health(ttl: 30, &probe)
    assert_equal 2, calls
    assert_equal "down", second[:status]
    assert_equal "flipped", second[:last_error]
  end

  test "health ttl stays clamped so ops cannot disable honesty" do
    previous = ENV["VIBE_SEARCH_HEALTH_TTL"]
    ENV["VIBE_SEARCH_HEALTH_TTL"] = "-1"
    assert_equal 0, MeilisearchClient.health_ttl
    ENV["VIBE_SEARCH_HEALTH_TTL"] = "99"
    assert_equal 15, MeilisearchClient.health_ttl
  ensure
    if previous.nil?
      ENV.delete("VIBE_SEARCH_HEALTH_TTL")
    else
      ENV["VIBE_SEARCH_HEALTH_TTL"] = previous
    end
  end
end

