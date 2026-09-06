# NFS incremental scan knobs. Read from ENV on each call so tests and
# rake can override without restarting. Zero / blank numeric caps mean unlimited.
class ScanSettings
  DEFAULT_CRON = "0 */6 * * *".freeze
  DEFAULT_MAX_SECONDS = 120
  DEFAULT_MAX_FILES = 5_000
  DEFAULT_MAX_FOLDERS = 200
  DEFAULT_PRUNE_BATCH = 50
  DEFAULT_DEEP_INTERVAL = 6.hours.to_i
  STALE_RUN_AFTER = 15.minutes

  class << self
    def max_seconds
      int("VIBE_SCAN_MAX_SECONDS", DEFAULT_MAX_SECONDS)
    end

    def max_files
      int("VIBE_SCAN_MAX_FILES", DEFAULT_MAX_FILES)
    end

    def max_folders
      int("VIBE_SCAN_MAX_FOLDERS", DEFAULT_MAX_FOLDERS)
    end

    def prune_batch
      [int("VIBE_SCAN_PRUNE_BATCH", DEFAULT_PRUNE_BATCH), 1].max
    end

    def deep_interval
      int("VIBE_SCAN_DEEP_INTERVAL", DEFAULT_DEEP_INTERVAL)
    end

    def trust_dir_mtime?
      bool("VIBE_SCAN_TRUST_DIR_MTIME", true)
    end

    def allow_empty_prune?
      bool("VIBE_SCAN_ALLOW_EMPTY_PRUNE", false)
    end

    def schedule_enabled?
      bool("VIBE_SCAN_SCHEDULE", true)
    end

    def cron
      ENV["VIBE_SCAN_CRON"].presence || DEFAULT_CRON
    end

    def as_api
      {
        max_seconds: max_seconds,
        max_files: max_files,
        max_folders: max_folders,
        prune_batch: prune_batch,
        deep_interval: deep_interval,
        trust_dir_mtime: trust_dir_mtime?,
        allow_empty_prune: allow_empty_prune?,
        schedule: schedule_enabled?,
        cron: cron
      }
    end

    def budgets_as_api
      {
        max_seconds: max_seconds,
        max_files: max_files,
        max_folders: max_folders
      }
    end

    private

    def int(key, default)
      value = ENV[key]
      return default if value.nil? || value.to_s.strip.empty?

      value.to_i
    end

    def bool(key, default)
      value = ENV[key]
      return default if value.nil? || value.to_s.strip.empty?

      ActiveModel::Type::Boolean.new.cast(value)
    end
  end
end
