require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false
  config.assume_ssl = ENV["RAILS_ASSUME_SSL"].present?
  config.force_ssl = ENV["RAILS_FORCE_SSL"].present?
  config.log_tags = [:request_id]
  config.logger = ActiveSupport::Logger.new($stdout)
    .tap { |logger| logger.formatter = Logger::Formatter.new }
    .then { |logger| ActiveSupport::TaggedLogging.new(logger) }
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")
  config.silence_healthcheck_path = "/up"
  config.active_support.report_deprecations = false
  config.active_record.dump_schema_after_migration = false
end
