require "sidekiq-cron"

redis_url = ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379/0")

Sidekiq.configure_server do |config|
  config.redis = { url: redis_url }
  config.on(:startup) do
    next if Rails.env.test?
    next unless defined?(Sidekiq::Cron)
    next unless ScanSettings.schedule_enabled?

    Sidekiq::Cron::Job.load_from_hash(
      "scheduled_library_scan" => {
        "cron" => ScanSettings.cron,
        "class" => "ScheduledScanJob",
        "queue" => "scan",
        "description" => "Incremental NFS library scan for every Library"
      }
    )
  end
end

Sidekiq.configure_client do |config|
  config.redis = { url: redis_url }
end
