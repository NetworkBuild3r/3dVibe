# Caps for ComputeGeometryDigestJob so a huge NAS mesh cannot pin a worker.
# Zero means that dimension is unlimited (same convention as DuplicateBudget).
class GeometryBudget
  DEFAULT_MAX_BYTES = 64 * 1024 * 1024
  DEFAULT_MAX_VERTS = 250_000
  DEFAULT_MAX_SECONDS = 20
  DEFAULT_MAX_ASSETS = 40
  DEFAULT_QUANT = 0.01

  attr_reader :max_bytes, :max_verts, :max_seconds, :max_assets, :quant, :verts

  def self.from_env
    new(
      max_bytes: ENV.fetch("VIBE_GEO_MAX_BYTES", DEFAULT_MAX_BYTES.to_s).to_i,
      max_verts: ENV.fetch("VIBE_GEO_MAX_VERTS", DEFAULT_MAX_VERTS.to_s).to_i,
      max_seconds: ENV.fetch("VIBE_GEO_MAX_SECONDS", DEFAULT_MAX_SECONDS.to_s).to_i,
      max_assets: ENV.fetch("VIBE_GEO_MAX_ASSETS", DEFAULT_MAX_ASSETS.to_s).to_i,
      quant: ENV.fetch("VIBE_GEO_QUANT", DEFAULT_QUANT.to_s).to_f
    )
  end

  def self.unlimited
    new(max_bytes: 0, max_verts: 0, max_seconds: 0, max_assets: 0, quant: DEFAULT_QUANT)
  end

  def initialize(max_bytes:, max_verts:, max_seconds:, max_assets: DEFAULT_MAX_ASSETS, quant: DEFAULT_QUANT, clock: nil)
    @max_bytes = max_bytes.to_i
    @max_verts = max_verts.to_i
    @max_seconds = max_seconds.to_i
    @max_assets = max_assets.to_i
    q = quant.to_f
    @quant = q.positive? ? q : DEFAULT_QUANT
    @verts = 0
    @clock = clock || -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
    @started = @clock.call
  end

  def see_vert!(count = 1)
    @verts += count
  end

  def elapsed
    @clock.call - @started
  end

  def oversized?(bytes)
    @max_bytes.positive? && bytes.to_i > @max_bytes
  end

  def time_exceeded?
    @max_seconds.positive? && elapsed >= @max_seconds
  end

  def vert_exceeded?
    @max_verts.positive? && @verts >= @max_verts
  end

  def exhausted?
    time_exceeded? || vert_exceeded?
  end

  def reason
    return "time" if time_exceeded?
    return "too_many_verts" if vert_exceeded?

    nil
  end
end
