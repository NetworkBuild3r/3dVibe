require "open3"
require "timeout"
require "time"

# Best-effort 7z/rar listing and single-member extract via the `7z` CLI.
# Zip/3mf never go through this path — they use rubyzip on the central directory.
class ArchiveShellLister
  Entry = Struct.new(:path, :directory, :size, :compressed_size, :mtime, keyword_init: true)

  class Error < StandardError; end

  def self.binary
    explicit = ENV["VIBE_7Z_BIN"].to_s
    return explicit if explicit.present? && File.executable?(explicit)

    ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).each do |dir|
      %w[7z 7za].each do |name|
        candidate = File.join(dir, name)
        return candidate if File.executable?(candidate)
      end
    end
    nil
  end

  def self.available?
    binary.present?
  end

  def self.list_timeout
    Integer(ENV.fetch("VIBE_ARCHIVE_LIST_TIMEOUT", "15"))
  end

  def initialize(path)
    @path = path
  end

  def available?
    self.class.available?
  end

  def each_entry
    self.class.parse_slt(list_slt).each { |entry| yield entry }
  end

  def extract_member(internal_path, destination, max_bytes:, max_seconds: nil)
    stream_member(internal_path, max_bytes: max_bytes, max_seconds: max_seconds) do |chunk|
      destination.write(chunk)
    end
  end

  # Yield 64 KiB chunks of one member. Kills `7z e -so` if the caller stops
  # iterating (HTTP abort / SPA navigate-away) or a budget trips.
  def stream_member(internal_path, max_bytes:, max_seconds: nil)
    bin = self.class.binary
    raise Error, "7z is not available" unless bin

    Open3.popen3(bin, "e", "-so", "-y", @path, internal_path) do |stdin, stdout, stderr, wait|
      stdin.close
      copied = 0
      buffer = String.new(capacity: ArchiveIndexer::CHUNK)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      begin
        while (chunk = stdout.read(ArchiveIndexer::CHUNK, buffer))
          copied += chunk.bytesize
          raise ArgumentError, "Refusing to load oversized member" if copied > max_bytes
          raise ArgumentError, "Archive member stream timed out" if timed_out?(started, max_seconds)

          yield chunk.dup
        end
        status = wait.value
        err = stderr.read
        raise Error, err.presence || "7z extract failed" unless status.success?
      ensure
        finish_process(wait, stdout, stderr)
      end
    end
  end

  def self.parse_slt(output)
    blocks = output.to_s.split(/\n(?=Path = )/)
    blocks.filter_map do |block|
      fields = {}
      block.each_line do |line|
        key, value = line.split(" = ", 2)
        next unless value

        fields[key.strip] = value.strip
      end
      path = fields["Path"]
      next if path.blank? || path == fields["Physical Name"]
      next if fields["Type"].present? && fields["Folder"].blank? && fields["Attributes"].blank?

      directory = fields["Folder"].to_s == "+" ||
        fields["Attributes"].to_s.upcase.include?("D") ||
        path.end_with?("/") || path.end_with?("\\")
      mtime =
        begin
          Time.parse(fields["Modified"]) if fields["Modified"].present?
        rescue ArgumentError
          nil
        end
      Entry.new(
        path: path,
        directory: directory,
        size: fields["Size"].to_i,
        compressed_size: fields["Packed Size"].to_i,
        mtime: mtime
      )
    end
  end

  private

  def timed_out?(started, max_seconds)
    limit = max_seconds.to_i
    return false if limit <= 0

    Process.clock_gettime(Process::CLOCK_MONOTONIC) - started > limit
  end

  def finish_process(wait, stdout, stderr)
    [stdout, stderr].each do |io|
      io.close unless io.closed?
    rescue IOError
      nil
    end
    if wait.alive?
      begin
        Process.kill("TERM", wait.pid)
      rescue Errno::ESRCH, Errno::ECHILD
        nil
      end
    end
    wait.join(2)
  rescue StandardError
    nil
  end

  def list_slt
    bin = self.class.binary
    raise Error, "7z is not available" unless bin

    stdout = stderr = ""
    status = nil
    Timeout.timeout(self.class.list_timeout) do
      stdout, stderr, status = Open3.capture3(bin, "l", "-slt", "-y", @path)
    end
    raise Error, stderr.presence || "7z listing failed" unless status&.success?

    stdout
  rescue Timeout::Error
    raise Error, "7z listing timed out"
  end
end
