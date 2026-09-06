# Per-job time / file / folder caps so a huge NFS tree cannot pin a Sidekiq
# worker. Zero means that dimension is unlimited. Resume is stored on ScanRun
# + ScanCursor, not here.
class ScanBudget
  attr_reader :files, :folders, :max_seconds, :max_files, :max_folders

  def self.from_env
    new(
      max_seconds: ScanSettings.max_seconds,
      max_files: ScanSettings.max_files,
      max_folders: ScanSettings.max_folders
    )
  end

  def self.unlimited
    new(max_seconds: 0, max_files: 0, max_folders: 0)
  end

  def initialize(max_seconds:, max_files:, max_folders:, clock: nil)
    @max_seconds = max_seconds.to_i
    @max_files = max_files.to_i
    @max_folders = max_folders.to_i
    @files = 0
    @folders = 0
    @clock = clock || -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
    @started = @clock.call
  end

  def see_file!(count = 1)
    @files += count
  end

  def see_folder!(count = 1)
    @folders += count
  end

  def elapsed
    @clock.call - @started
  end

  def time_exceeded?
    @max_seconds.positive? && elapsed >= @max_seconds
  end

  def file_exceeded?
    @max_files.positive? && @files >= @max_files
  end

  def folder_exceeded?
    @max_folders.positive? && @folders >= @max_folders
  end

  def file_or_time_exceeded?
    time_exceeded? || file_exceeded?
  end

  def exhausted?
    time_exceeded? || file_exceeded? || folder_exceeded?
  end

  def reason
    return "time" if time_exceeded?
    return "files" if file_exceeded?
    return "folders" if folder_exceeded?

    nil
  end
end
