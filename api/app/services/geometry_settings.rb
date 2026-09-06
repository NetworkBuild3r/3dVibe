# Knobs for on-demand mesh fingerprinting. Read from ENV so tests can override
# without restart. Zero numeric caps mean unlimited for that dimension.
class GeometrySettings
  DEFAULT_MAX_SECONDS = 20
  DEFAULT_MAX_BYTES = 48.megabytes
  DEFAULT_MAX_FACES = 500_000
  DEFAULT_MAX_ASSETS = 40
  DEFAULT_QUANT = 1_000
  METHOD = "normalized_quantized_vertices"

  class << self
    def max_seconds
      int("VIBE_GEOM_MAX_SECONDS", DEFAULT_MAX_SECONDS)
    end

    def max_bytes
      int("VIBE_GEOM_MAX_BYTES", DEFAULT_MAX_BYTES)
    end

    def max_faces
      int("VIBE_GEOM_MAX_FACES", DEFAULT_MAX_FACES)
    end

    def max_assets
      int("VIBE_GEOM_MAX_ASSETS", DEFAULT_MAX_ASSETS)
    end

    def quant
      [int("VIBE_GEOM_QUANT", DEFAULT_QUANT), 1].max
    end

    def method_name
      METHOD
    end

    private

    def int(key, default)
      value = ENV[key]
      return default if value.nil? || value.to_s.strip.empty?

      value.to_i
    end
  end
end
