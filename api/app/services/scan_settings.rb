# NFS incremental scan knobs. Read from ENV on each call so tests and
# rake can override without restarting. Zero / blank numeric caps mean unlimited.
class ScanSettings
  DEFAULT_CRON = "0 */6 * * *".freeze
  DEFAULT_MAX_SECONDS = 120
  DEFAULT_MAX_FILES = 5_000
  DEFAULT_MAX_FOLDERS = 200
  DEFAULT_PRUNE_BATCH = 50
  DEFAULT_DEEP_INTERVAL = 6.hours.to_i
  DEFAULT_QUEUE = "scan".freeze
  DEFAULT_CONCURRENCY = 1
  DEFAULT_WORKER_CONCURRENCY = 5
  MAX_CONCURRENCY = 32
  STALE_RUN_AFTER = 15.minutes
  # Queues that serve API-critical work. IncrementalScanJob must not share
  # this pool or an overnight deep walk can occupy every Sidekiq thread.
  CRITICAL_QUEUES = %w[default print search previews covers curation duplicates].freeze
  # Sidekiq weights on the default capsule. Covers stay below API/print so a
  # NAS-scale GenerateCoverJob backlog cannot starve request-driven work.
  # Scan is not listed — it runs on the isolated capsule.
  QUEUE_WEIGHTS = {
    "default" => 10,
    "print" => 8,
    "search" => 5,
    "previews" => 3,
    "covers" => 2,
    "curation" => 3,
    "duplicates" => 2
  }.freeze

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

    # Isolated Sidekiq queue for IncrementalScanJob / ScheduledScanJob.
    # Reserved critical names fall back to "scan" so NFS work cannot land
    # on print/search/covers and starve API-triggered jobs.
    def queue
      raw = ENV["VIBE_SCAN_QUEUE"].to_s.strip.downcase
      sanitized = raw.gsub(/[^a-z0-9_-]/, "")
      return DEFAULT_QUEUE if sanitized.empty? || CRITICAL_QUEUES.include?(sanitized)

      sanitized
    end

    def concurrency
      clamp_concurrency(int("VIBE_SCAN_CONCURRENCY", DEFAULT_CONCURRENCY), default: DEFAULT_CONCURRENCY)
    end

    def worker_concurrency
      clamp_concurrency(int("VIBE_SIDEKIQ_CONCURRENCY", DEFAULT_WORKER_CONCURRENCY), default: DEFAULT_WORKER_CONCURRENCY)
    end

    def isolated_queues
      CRITICAL_QUEUES - [queue]
    end

    def weighted_isolated_queues
      isolated_queues.map { |name| [name, QUEUE_WEIGHTS[name] || 1] }
    end

    def sidekiq_layout
      {
        default: { concurrency: worker_concurrency, queues: weighted_isolated_queues },
        scan: { concurrency: concurrency, queues: [queue] }
      }
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
        cron: cron,
        queue: queue,
        concurrency: concurrency,
        worker_concurrency: worker_concurrency
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

    def clamp_concurrency(value, default:)
      n = value.to_i
      n = default if n < 1
      [n, MAX_CONCURRENCY].min
    end
  end
end
