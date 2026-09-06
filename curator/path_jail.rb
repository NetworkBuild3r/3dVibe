# frozen_string_literal: true

# Mirrors Rails LibraryPathJail: first-level model folders, no escapes,
# no hidden segments, no deletes. The sidecar never touches the filesystem
# except a read-only GET fallback listing.
module VibeCurator
  class PathJail
    def initialize(library_root)
      @root = File.expand_path(library_root.to_s)
    end

    def valid_model_folder?(name)
      parts = segments(name)
      parts.size == 1 && valid_segment?(parts.first)
    end

    def valid_relative?(path)
      parts = segments(path)
      parts.any? && parts.all? { |part| valid_segment?(part) }
    end

    def first_level(name)
      parts = segments(name)
      return unless parts.size == 1 && valid_segment?(parts.first)

      parts.first
    end

    def jailed_relative(path)
      cleaned = relativize(path)
      return unless valid_relative?(cleaned)

      segments(cleaned).join("/")
    end

    def looks_like_escape?(path)
      value = path.to_s.tr("\\", "/").strip
      return true if value.empty?
      return true if value.start_with?("/") && !under_root?(value)
      return true if segments(value).any? { |part| part == ".." || part == "." || part.start_with?(".") }

      false
    end

    private

    def relativize(path)
      value = path.to_s.tr("\\", "/").strip
      return value.delete_prefix("/") if under_root?(value)

      value
    end

    def under_root?(path)
      return false unless path.start_with?("/")

      expanded = File.expand_path(path)
      expanded == @root || expanded.start_with?("#{@root}/")
    end

    def segments(value)
      value.to_s.tr("\\", "/").split("/").reject(&:empty?)
    end

    def valid_segment?(part)
      part.to_s != "" && part != "." && part != ".." && !part.include?("\0") && !part.start_with?(".")
    end
  end
end
