require "test_helper"

class GeometryBudgetTest < ActiveSupport::TestCase
  test "zero caps are unlimited" do
    budget = GeometryBudget.unlimited
    10_000.times { budget.see_vert! }
    refute budget.exhausted?
    refute budget.oversized?(10**12)
    assert_nil budget.reason
  end

  test "vert cap stops after the configured number of vertices" do
    budget = GeometryBudget.new(max_bytes: 0, max_verts: 2, max_seconds: 0)
    budget.see_vert!
    refute budget.vert_exceeded?
    budget.see_vert!
    assert budget.vert_exceeded?
    assert_equal "too_many_verts", budget.reason
  end

  test "byte cap is a prefilter" do
    budget = GeometryBudget.new(max_bytes: 100, max_verts: 0, max_seconds: 0)
    refute budget.oversized?(100)
    assert budget.oversized?(101)
  end

  test "time cap uses a monotonic clock" do
    now = 0.0
    budget = GeometryBudget.new(max_bytes: 0, max_verts: 0, max_seconds: 2, clock: -> { now })
    now = 1.5
    refute budget.time_exceeded?
    now = 2.0
    assert budget.time_exceeded?
    assert_equal "time", budget.reason
  end

  test "from_env reads VIBE_GEO_* knobs" do
    ENV["VIBE_GEO_MAX_BYTES"] = "4096"
    ENV["VIBE_GEO_MAX_VERTS"] = "12"
    ENV["VIBE_GEO_MAX_SECONDS"] = "3"
    ENV["VIBE_GEO_MAX_ASSETS"] = "7"
    ENV["VIBE_GEO_QUANT"] = "0.5"

    budget = GeometryBudget.from_env
    assert_equal 4096, budget.max_bytes
    assert_equal 12, budget.max_verts
    assert_equal 3, budget.max_seconds
    assert_equal 7, budget.max_assets
    assert_in_delta 0.5, budget.quant
  ensure
    ENV.delete("VIBE_GEO_MAX_BYTES")
    ENV.delete("VIBE_GEO_MAX_VERTS")
    ENV.delete("VIBE_GEO_MAX_SECONDS")
    ENV.delete("VIBE_GEO_MAX_ASSETS")
    ENV.delete("VIBE_GEO_QUANT")
  end
end
