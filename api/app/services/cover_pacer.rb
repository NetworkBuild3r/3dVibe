# Rate-limit / priority / batch for GenerateCoverJob so a NAS-scale scan
# does not dump every pending cover onto Sidekiq at once (API-starving
# enqueue storms, pending→ready cliffs).
#
# Scan still marks cover_status=pending immediately. This pacer decides
# how many GenerateCoverJob rows sit on the :covers queue.
class CoverPacer
  DEFAULT_QUEUE_MAX = 40
  DEFAULT_BATCH = 20
  DEFAULT_PACE_SECONDS = 2.0
  UNLIMITED_DRAIN = 100
  MUTEX = Mutex.new

  PRIORITY_SQL = <<~SQL.squish.freeze
    CASE
      WHEN vibe_models.cover_status = 'pending'
        AND (assets.filename ~* 'cover|preview|thumb|hero'
          OR assets.relative_path ~* 'cover|preview|thumb|hero') THEN 0
      WHEN vibe_models.cover_status = 'pending'
        AND assets.kind IN ('png','jpg','jpeg','webp','gif') THEN 1
      WHEN vibe_models.cover_status = 'pending' THEN 2
      ELSE 3
    END
  SQL

  class << self
    def submit!(payload)
      data = CoverGenerator.stringify(payload)
      if admit?
        enqueue_generate!(data)
        record_admit!
        :enqueued
      else
        CoverBacklogJob.ensure_scheduled!
        :deferred
      end
    end

    def drain!
      room = enqueue_room
      if room <= 0
        CoverBacklogJob.ensure_scheduled! if leftover?
        return { enqueued: 0, reason: :queue_full }
      end

      models = pick_backlog(room)
      count = 0
      models.each do |model|
        payload = CoverEnqueue.payload_for(model)
        next unless payload

        enqueue_generate!(payload)
        count += 1
      end
      CoverBacklogJob.ensure_scheduled! if leftover?
      { enqueued: count }
    end

    def nudge!
      CoverBacklogJob.ensure_scheduled! if leftover?
    end

    def queue_max
      read_int("VIBE_COVER_QUEUE_MAX", DEFAULT_QUEUE_MAX)
    end

    def batch_size
      read_int("VIBE_COVER_BATCH", DEFAULT_BATCH)
    end

    def pace_seconds
      raw = ENV.fetch("VIBE_COVER_PACE_SECONDS", DEFAULT_PACE_SECONDS).to_f
      raw.negative? ? 0.0 : raw
    end

    def queue_unlimited?
      queue_max <= 0
    end

    def batch_unlimited?
      batch_size <= 0
    end

    def queued_generate_count
      generate_entries.size
    end

    def queued_model_ids
      generate_entries.filter_map { |entry| entry_model_id(entry) }.to_set
    end

    def backlog_job_queued?
      job_entries("CoverBacklogJob").any?
    end

    def leftover?
      scope = backlog_scope
      already = queued_model_ids.to_a
      scope = scope.where.not(id: already) if already.any?
      scope.exists?
    end

    def reset!
      MUTEX.synchronize do
        @burst = 0
        @burst_at = nil
      end
    end

    def enqueue_generate!(payload)
      GenerateCoverJob.perform_later(payload)
    end

    private

    def admit?
      expire_burst!
      return false if !queue_unlimited? && queued_generate_count >= queue_max
      return false if !batch_unlimited? && burst >= effective_batch

      true
    end

    def expire_burst!
      window = pace_seconds
      return if window <= 0

      MUTEX.synchronize do
        now = monotonic
        @burst = 0 if @burst_at && (now - @burst_at) >= window
      end
    end

    def record_admit!
      MUTEX.synchronize do
        now = monotonic
        window = pace_seconds
        @burst = 0 if window.positive? && @burst_at && (now - @burst_at) >= window
        @burst = @burst.to_i + 1
        @burst_at = now if @burst == 1
      end
    end

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def burst
      MUTEX.synchronize { @burst.to_i }
    end

    def effective_batch
      batch_unlimited? ? UNLIMITED_DRAIN : batch_size
    end

    def enqueue_room
      queued = queued_generate_count
      depth = queue_unlimited? ? UNLIMITED_DRAIN : [queue_max - queued, 0].max
      cap = batch_unlimited? ? UNLIMITED_DRAIN : batch_size
      [depth, cap].min
    end

    def pick_backlog(limit)
      already = queued_model_ids.to_a
      scope = backlog_scope
      scope = scope.where.not(id: already) if already.any?
      scope
        .joins("LEFT JOIN assets ON assets.id = vibe_models.cover_asset_id")
        .select("vibe_models.*")
        .order(Arel.sql(PRIORITY_SQL), updated_at: :desc, id: :desc)
        .limit(limit)
        .to_a
    end

    def backlog_scope
      VibeModel.where(cover_status: VibeModel::COVER_PENDING)
    end

    def generate_entries
      job_entries("GenerateCoverJob")
    end

    def job_entries(class_name)
      adapter_entries.select { |entry| entry_class(entry) == class_name }
    end

    def adapter_entries
      adapter = ActiveJob::Base.queue_adapter
      if adapter.respond_to?(:enqueued_jobs)
        Array(adapter.enqueued_jobs) + scheduled_from(adapter)
      else
        sidekiq_entries
      end
    rescue StandardError => e
      Rails.logger.warn("[CoverPacer] queue inspect failed: #{e.message}")
      []
    end

    def scheduled_from(adapter)
      return [] unless adapter.respond_to?(:scheduled_jobs)

      Array(adapter.scheduled_jobs)
    end

    def sidekiq_entries
      return [] unless defined?(Sidekiq::Queue)

      require "sidekiq/api" unless defined?(Sidekiq::Queue)
      jobs = []
      Sidekiq::Queue.new("covers").each { |job| jobs << sidekiq_entry(job) }
      Sidekiq::ScheduledSet.new.each do |job|
        next unless job.queue == "covers"

        jobs << sidekiq_entry(job)
      end
      jobs
    rescue StandardError => e
      Rails.logger.warn("[CoverPacer] sidekiq inspect failed: #{e.message}")
      []
    end

    def sidekiq_entry(job)
      args = Array(job.args)
      wrapper = args.first
      if wrapper.is_a?(Hash) && wrapper["job_class"]
        wrapper
      else
        { "job_class" => job.display_class || job.klass, "arguments" => args }
      end
    end

    def entry_class(entry)
      if entry.is_a?(Hash)
        (entry["job_class"] || entry[:job_class] || entry[:job]&.name).to_s
      else
        entry.class.name
      end
    end

    def entry_model_id(entry)
      args = if entry.is_a?(Hash)
        entry["arguments"] || entry[:arguments] || entry[:args]
      end
      payload = Array(args).first
      payload = payload.stringify_keys if payload.respond_to?(:stringify_keys)
      payload.is_a?(Hash) ? payload["model_id"] : nil
    end

    def read_int(key, default)
      ENV.fetch(key, default).to_i
    end
  end
end
