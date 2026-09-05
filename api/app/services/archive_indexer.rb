require "zip"

class ArchiveIndexer
  def initialize(asset)
    @asset = asset
  end

  def index!
    path = @asset.absolute_path
    return unless File.file?(path)

    case @asset.kind
    when "zip", "3mf"
      index_zip(path)
    when "7z", "rar"
      index_opaque_archive(path)
    end
  end

  def stream_member(internal_path)
    raise ArgumentError, "Only zip-family archives can stream a member" unless %w[zip 3mf].include?(@asset.kind)

    Zip::File.open(@asset.absolute_path) do |zip|
      entry = zip.find_entry(internal_path)
      raise ActiveRecord::RecordNotFound, "Missing archive member" unless entry
      raise "Refusing to load oversized member" if entry.size && entry.size > 32.megabytes

      yield entry, entry.get_input_stream
    end
  end

  private

  def index_zip(path)
    seen = []
    Zip::File.open(path) do |zip|
      zip.each do |entry|
        seen << entry.name
        member = @asset.archive_members.find_or_initialize_by(internal_path: entry.name)
        member.directory = entry.directory?
        member.compressed_size = entry.compressed_size
        member.uncompressed_size = entry.size
        member.mtime = entry.time
        member.save!
      end
    end
    @asset.archive_members.where.not(internal_path: seen).delete_all
  end

  # 7z/rar listing is deferred; record a single placeholder so the UI can show the archive exists.
  def index_opaque_archive(path)
    member = @asset.archive_members.find_or_initialize_by(internal_path: "(listing pending)")
    member.directory = false
    member.uncompressed_size = File.size(path)
    member.compressed_size = File.size(path)
    member.mtime = File.mtime(path)
    member.save!
    @asset.archive_members.where.not(id: member.id).delete_all
  end
end
