require "sidekiq-cron"

redis_url = ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379/0")

Sidekiq.configure_server do |config|
  config.redis = { url: redis_url }

  # Isolate IncrementalScanJob onto its own capsule so overnight deep walks
  # (and budgeted resume slices) cannot occupy every worker thread.
  layout = ScanSettings.sidekiq_layout
  config.concurrency = layout[:default][:concurrency]
  config.queues = layout[:default][:queues]
  config.capsule("scan") do |cap|
    cap.concurrency = layout[:scan][:concurrency]
    cap.queues = layout[:scan][:queues]
  end

  config.on(:startup) do
    next if Rails.env.test?
    next unless defined?(Sidekiq::Cron)
    next unless ScanSettings.schedule_enabled?

    Sidekiq::Cron::Job.load_from_hash(
      "scheduled_library_scan" => {
        "cron" => ScanSettings.cron,
        "class" => "ScheduledScanJob",
        "queue" => ScanSettings.queue,
        "description" => "Incremental NFS library scan for every Library"
      }
    )
  end
end

Sidekiq.configure_client do |config|
  config.redis = { url: redis_url }
end
