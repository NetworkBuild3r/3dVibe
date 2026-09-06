# Geometry digest for path-jailed mesh files (stl / obj / 3mf mesh only).
#
# Choice: normalize (center + unit AABB scale) then SHA-256 sorted quantized
# vertices (`qv1:…`). Re-exports change bytes (ASCII↔binary STL, STL↔OBJ↔3MF)
# but keep the same tessellation; a content hash misses those. A trimesh-style
# area/volume/euler identifier is more collision-prone, so it is not what we
# store. Huge meshes skip or time out. 3MF streams the `.model` member — the
# archive is never slurped into RAM.
#
# Returns the digest string (or nil). Persist via GeometryWriteback.apply!.
require "zip"

class GeometryFingerprint
  VERSION = "qv1".freeze
  KINDS = %w[stl obj 3mf].freeze
  TRANSIENT_ERRNO = [
    Errno::EACCES, Errno::EAGAIN, Errno::EBUSY, Errno::EHOSTUNREACH,
    Errno::EIO, Errno::ENETDOWN, Errno::ENOENT, Errno::ESTALE
  ].freeze

  class Skip < StandardError; end

  def self.compute(asset, budget: nil, clock: nil)
    new(asset, budget: budget, clock: clock).compute
  end

  def initialize(asset, budget: nil, clock: nil)
    @asset = asset
    @budget = budget || GeometrySettings
    @clock = clock || -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
    @started = @clock.call
    @bytes_read = 0
  end

  def compute
    return @asset.geometry_digest if @asset.geometry_digest.present?
    return unless fingerprintable?

    path = jailed_path
    size = File.size(path)
    if @budget.max_bytes.positive? && size > @budget.max_bytes
      raise Skip, "file exceeds #{@budget.max_bytes} bytes"
    end

    parse!(path).digest!
  rescue Skip, ArgumentError, *TRANSIENT_ERRNO
    nil
  end

  private

  def fingerprintable?
    KINDS.include?(@asset.kind)
  end

  def jailed_path
    model = @asset.vibe_model
    raise ArgumentError, "asset is not in a library" unless model&.library

    LibraryPathJail.new(model.library.root_path).resolve_file(model.folder_name, @asset.relative_path)
  end

  def parse!(path)
    builder = MeshBuilder.new(budget: @budget, clock: @clock, started: @started)
    File.open(path, "rb") do |io|
      case @asset.kind
      when "stl" then parse_stl(io, builder)
      when "obj" then parse_obj(io, builder)
      when "3mf" then parse_3mf(path, builder)
      else
        raise Skip, "unsupported kind #{@asset.kind}"
      end
    end
    builder
  end

  def parse_stl(io, builder)
    raise Skip, "empty stl" if io.stat.size.to_i.zero?

    if binary_stl?(io)
      parse_binary_stl(io, builder)
    else
      io.rewind
      @bytes_read = 0
      parse_ascii_stl(io, builder)
    end
  end

  def binary_stl?(io)
    size = io.stat.size
    header = io.read(80)
    return false if header.nil? || size < 84 || (size - 84) % 50 != 0

    count = io.read(4)&.unpack1("V")
    io.rewind
    @bytes_read = 0
    return false unless count && (84 + (count * 50) == size)

    if header.lstrip.downcase.start_with?("solid")
      sample = io.read(1_024)
      io.rewind
      @bytes_read = 0
      return false if sample.to_s.downcase.include?("facet") || sample.to_s.downcase.include?("vertex")
    end

    io.seek(80)
    @bytes_read = 80
    true
  rescue Errno::ENOENT
    false
  end

  def parse_binary_stl(io, builder)
    count = read!(io, 4)&.unpack1("V")
    raise Skip, "invalid binary stl" unless count

    count.times do
      chunk = read!(io, 50)
      raise Skip, "truncated binary stl" if chunk.nil? || chunk.bytesize < 50

      floats = chunk.unpack("e12")
      builder.add_triangle(floats[3, 3], floats[6, 3], floats[9, 3])
    end
  end

  def parse_ascii_stl(io, builder)
    verts = []
    io.each_line do |line|
      note_bytes!(line.bytesize)
      token = line.strip
      next if token.empty?

      if token.downcase.start_with?("vertex")
        parts = token.split
        verts << [parts[1].to_f, parts[2].to_f, parts[3].to_f] if parts.size >= 4
        if verts.size == 3
          builder.add_triangle(verts[0], verts[1], verts[2])
          verts = []
        end
      end
    end
  end

  def parse_obj(io, builder)
    io.each_line do |line|
      note_bytes!(line.bytesize)
      token = line.strip
      next if token.empty? || token.start_with?("#")

      parts = token.split
      case parts[0]
      when "v"
        next unless parts.size >= 4

        builder.add_vertex(parts[1].to_f, parts[2].to_f, parts[3].to_f)
      when "f"
        idxs = parts[1..].filter_map { |spec| spec.split("/", 2).first.to_i }
        next if idxs.size < 3

        (1...(idxs.size - 1)).each do |i|
          builder.add_indexed_triangle(idxs[0], idxs[i], idxs[i + 1])
        end
      end
    end
  end

  def parse_3mf(path, builder)
    Zip::File.open(path.to_s) do |zip|
      entry = zip.entries.find { |item| mesh_model_entry?(item) }
      raise Skip, "3mf has no mesh model" unless entry
      if @budget.max_bytes.positive? && entry.size.to_i > @budget.max_bytes
        raise Skip, "3mf mesh exceeds #{@budget.max_bytes} bytes"
      end

      entry.get_input_stream { |io| parse_3mf_xml(io, builder) }
    end
  rescue Zip::Error => e
    raise Skip, "3mf zip: #{e.message}"
  end

  def parse_3mf_xml(io, builder)
    buffer = +""
    while (chunk = io.read(16 * 1024))
      note_bytes!(chunk.bytesize)
      buffer << chunk
      consume_3mf_tags!(buffer, builder)
    end
    consume_3mf_tags!(buffer, builder, flush: true)
  end

  def consume_3mf_tags!(buffer, builder, flush: false)
    while (idx = buffer.index(">"))
      tag = buffer.slice!(0..idx)
      next unless tag.include?("<")

      apply_3mf_tag(tag, builder)
    end
    buffer.clear if flush || (buffer.size > 8_192 && !buffer.include?("<"))
  end

  def apply_3mf_tag(tag, builder)
    if tag.match?(/<vertex\b/i)
      x = tag[/\bx=["']?(-?[\d.eE+-]+)/, 1]
      y = tag[/\by=["']?(-?[\d.eE+-]+)/, 1]
      z = tag[/\bz=["']?(-?[\d.eE+-]+)/, 1]
      builder.add_vertex(x.to_f, y.to_f, z.to_f) if x && y && z
    elsif tag.match?(/<triangle\b/i)
      v1 = tag[/\bv1=["']?(\d+)/, 1]
      v2 = tag[/\bv2=["']?(\d+)/, 1]
      v3 = tag[/\bv3=["']?(\d+)/, 1]
      builder.add_indexed_triangle(v1.to_i, v2.to_i, v3.to_i) if v1 && v2 && v3
    end
  end

  def mesh_model_entry?(entry)
    return false if entry.directory?

    name = entry.name.to_s.tr("\\", "/").downcase
    return false if name.split("/").any? { |part| part.start_with?(".") }

    name.end_with?(".model") && name.include?("3d")
  end

  def read!(io, n)
    chunk = io.read(n)
    note_bytes!(chunk.bytesize) if chunk
    chunk
  end

  def note_bytes!(n)
    @bytes_read += n
    if @budget.max_bytes.positive? && @bytes_read > @budget.max_bytes
      raise Skip, "read exceeds #{@budget.max_bytes} bytes"
    end
  end

  class MeshBuilder
    def initialize(budget:, clock:, started:)
      @budget = budget
      @clock = clock
      @started = started
      @vertices = []
      @faces = 0
    end

    def add_vertex(x, y, z)
      check_budget!
      @vertices << [x.to_f, y.to_f, z.to_f]
    end

    def add_triangle(a, b, c)
      add_vertex(*a)
      add_vertex(*b)
      add_vertex(*c)
      @faces += 1
      check_faces!
    end

    def add_indexed_triangle(*_indexes)
      check_budget!
      @faces += 1
      check_faces!
    end

    def digest!
      raise Skip, "empty mesh" if @vertices.empty? || @faces.zero?

      cx = 0.0
      cy = 0.0
      cz = 0.0
      @vertices.each do |x, y, z|
        cx += x
        cy += y
        cz += z
      end
      n = @vertices.size.to_f
      cx /= n
      cy /= n
      cz /= n

      minx = maxx = @vertices[0][0] - cx
      miny = maxy = @vertices[0][1] - cy
      minz = maxz = @vertices[0][2] - cz
      @vertices.each do |x, y, z|
        dx = x - cx
        dy = y - cy
        dz = z - cz
        minx = dx if dx < minx
        maxx = dx if dx > maxx
        miny = dy if dy < miny
        maxy = dy if dy > maxy
        minz = dz if dz < minz
        maxz = dz if dz > maxz
      end
      extent = [maxx - minx, maxy - miny, maxz - minz].max
      scale = extent > 1e-12 ? (1.0 / extent) : 1.0
      quant = @budget.quant

      grid = @vertices.map do |x, y, z|
        [
          ((x - cx) * scale * quant).round,
          ((y - cy) * scale * quant).round,
          ((z - cz) * scale * quant).round
        ]
      end
      grid.uniq!
      grid.sort!

      payload = VERSION.dup.force_encoding(Encoding::BINARY)
      payload << [grid.size, @faces].pack("Q<2")
      payload << grid.flatten.pack("l<*")
      "#{VERSION}:#{Digest::SHA256.hexdigest(payload)}"
    end

    private

    def check_budget!
      if @budget.max_seconds.positive? && (@clock.call - @started) >= @budget.max_seconds
        raise Skip, "timed out after #{@budget.max_seconds}s"
      end
    end

    def check_faces!
      if @budget.max_faces.positive? && @faces > @budget.max_faces
        raise Skip, "exceeds #{@budget.max_faces} faces"
      end
    end
  end
end
