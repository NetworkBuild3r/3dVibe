# Caps streamed hashing so an on-demand analyze cannot pin a Sidekiq worker.
# Zero means that dimension is unlimited. Resume is implicit: persisted
# content_digest rows are skipped on the next run.
class DuplicateBudget
  attr_reader :files, :max_seconds, :max_files

  def self.from_env
    new(
      max_seconds: ENV.fetch("VIBE_DUP_MAX_SECONDS", "60").to_i,
      max_files: ENV.fetch("VIBE_DUP_MAX_FILES", "2000").to_i
    )
  end

  def self.unlimited
    new(max_seconds: 0, max_files: 0)
  end

  def initialize(max_seconds:, max_files:, clock: nil)
    @max_seconds = max_seconds.to_i
    @max_files = max_files.to_i
    @files = 0
    @clock = clock || -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
    @started = @clock.call
  end

  def see_file!(count = 1)
    @files += count
  end

  def elapsed
    @clock.call - @started
  end

  def exhausted?
    time_exceeded? || file_exceeded?
  end

  def time_exceeded?
    @max_seconds.positive? && elapsed >= @max_seconds
  end

  def file_exceeded?
    @max_files.positive? && @files >= @max_files
  end

  def reason
    return "time" if time_exceeded?
    return "files" if file_exceeded?

    nil
  end
end
