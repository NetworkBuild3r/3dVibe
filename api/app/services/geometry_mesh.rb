require "digest"
require "set"
require "zip"

# Stream a loose STL / OBJ / 3MF and build an order-independent geometry
# identifier. Vertices are quantized; colors, normals, names, and 3MF
# component transforms are dropped. Never slurps an archive into RAM.
class GeometryMesh
  CHUNK = 64 * 1024
  STL_HEADER = 80
  STL_TRI = 50

  class LimitError < StandardError
    attr_reader :reason

    def initialize(reason)
      @reason = reason.to_s
      super(@reason)
    end
  end

  def initialize(budget)
    @budget = budget
    @unique_verts = Set.new
    @unique_faces = Set.new
    @indexed = []
  end

  def parse!(path, kind:)
    case kind.to_s
    when "stl" then parse_stl(path)
    when "obj" then parse_obj(path)
    when "3mf" then parse_3mf(path)
    else
      raise LimitError, "non_mesh"
    end
    self
  end

  def empty?
    @unique_verts.empty?
  end

  def hexdigest
    digest = Digest::SHA256.new
    digest.update("mesh-v1")
    verts = @unique_verts.to_a.sort!
    digest.update([verts.size].pack("Q>"))
    verts.each { |vert| digest.update(vert) }
    faces = @unique_faces.to_a.sort!
    digest.update([faces.size].pack("Q>"))
    faces.each { |face| digest.update(face) }
    digest.hexdigest
  end

  private

  def parse_stl(path)
    size = File.size(path)
    if binary_stl?(path, size)
      parse_binary_stl(path, size)
    else
      parse_ascii_stl(path)
    end
  end

  def binary_stl?(path, size)
    return false if size < STL_HEADER + 4

    File.open(path, "rb") do |io|
      io.read(STL_HEADER)
      count = io.read(4)&.unpack1("V")
      return false unless count

      size == STL_HEADER + 4 + (count * STL_TRI)
    end
  end

  def parse_binary_stl(path, size)
    File.open(path, "rb") do |io|
      io.read(STL_HEADER)
      count = io.read(4)&.unpack1("V").to_i
      raise LimitError, "too_large" if @budget.oversized?(size)
      raise LimitError, "too_many_verts" if over_vert_cap?(count * 3)

      count.times do
        rec = io.read(STL_TRI)
        break unless rec && rec.bytesize == STL_TRI

        floats = rec.byteslice(12, 36)&.unpack("e9")
        next unless floats && floats.size == 9

        add_triangle!(floats[0, 3], floats[3, 3], floats[6, 3])
      end
    end
  end

  def parse_ascii_stl(path)
    verts = []
    File.open(path, "rb") do |io|
      io.each_line do |line|
        check_time!
        stripped = line.to_s.strip
        next unless stripped.downcase.start_with?("vertex")

        coords = parse_floats(stripped.split[1, 3])
        next unless coords

        packed = add_vert!(*coords)
        verts << packed
        if verts.size == 3
          add_face!(verts[0], verts[1], verts[2])
          verts.clear
        end
      end
    end
  end

  def parse_obj(path)
    reset_indexed!
    File.open(path, "rb") do |io|
      io.each_line do |line|
        check_time!
        line = line.to_s
        if line.start_with?("v ")
          coords = parse_floats(line.split[1, 3])
          next unless coords

          @indexed << add_vert!(*coords)
        elsif line.start_with?("f ")
          indices = line.split[1..].filter_map { |token| token.split("/", 2).first&.to_i }
          add_indexed_polygon!(indices)
        end
      end
    end
  end

  def parse_3mf(path)
    Zip::File.open(path.to_s) do |zip|
      zip.each do |entry|
        next if entry.directory?
        next unless model_entry?(entry)

        raise LimitError, "too_large" if entry.size && @budget.oversized?(entry.size)

        reset_indexed!
        parse_3mf_xml(entry.get_input_stream)
      end
    end
  end

  def model_entry?(entry)
    name = entry.name.to_s.tr("\\", "/").downcase
    name.end_with?(".model")
  end

  def parse_3mf_xml(io)
    leftover = +""
    copied = 0
    while (chunk = io.read(CHUNK))
      copied += chunk.bytesize
      raise LimitError, "too_large" if @budget.oversized?(copied)
      check_time!

      leftover << chunk
      consume_3mf_tags!(leftover)
      trim_3mf_buffer!(leftover)
    end
    consume_3mf_tags!(leftover)
  end

  def consume_3mf_tags!(buffer)
    while (match = buffer.match(/<\/?mesh\b[^>]*>|<(?:vertex|triangle)\b[^>]*>/i))
      tag = match[0]
      buffer.slice!(0, match.end(0))
      if tag.start_with?("</") || tag.match?(/\A<mesh\b/i)
        reset_indexed!
        next
      end

      if tag.match?(/\A<vertex\b/i)
        x = xml_attr(tag, "x")
        y = xml_attr(tag, "y")
        z = xml_attr(tag, "z")
        next unless x && y && z

        @indexed << add_vert!(x, y, z)
      elsif tag.match?(/\A<triangle\b/i)
        i1 = xml_attr(tag, "v1")
        i2 = xml_attr(tag, "v2")
        i3 = xml_attr(tag, "v3")
        next unless i1 && i2 && i3

        add_indexed_polygon!([i1.to_i + 1, i2.to_i + 1, i3.to_i + 1])
      end
    end
  end

  def trim_3mf_buffer!(buffer)
    return if buffer.bytesize <= CHUNK

    last = buffer.rindex("<")
    if last
      buffer.replace(buffer[last..])
    else
      buffer.clear
    end
  end

  def xml_attr(tag, name)
    match = tag.match(/\b#{Regexp.escape(name)}\s*=\s*["']?([-+0-9.eE]+)["']?/i)
    match && match[1]
  end

  def add_triangle!(a, b, c)
    pa = add_vert!(*a)
    pb = add_vert!(*b)
    pc = add_vert!(*c)
    add_face!(pa, pb, pc)
  end

  def add_vert!(x, y, z)
    check_limits!
    @budget.see_vert!
    packed = pack_quantized(x, y, z)
    @unique_verts.add(packed)
    packed
  end

  def add_face!(a, b, c)
    return if a.nil? || b.nil? || c.nil?
    return if a == b || b == c || a == c

    @unique_faces.add([a, b, c].sort.join)
  end

  def add_indexed_polygon!(indices)
    return if indices.size < 3

    (1...(indices.size - 1)).each do |i|
      a = resolve_index(indices[0])
      b = resolve_index(indices[i])
      c = resolve_index(indices[i + 1])
      add_face!(a, b, c)
    end
  end

  def resolve_index(index)
    return if index.nil? || index == 0

    pos = index.positive? ? index - 1 : @indexed.size + index
    return if pos.negative?

    @indexed[pos]
  end

  def reset_indexed!
    @indexed = []
  end

  def pack_quantized(x, y, z)
    q = @budget.quant
    [
      (x.to_f / q).round,
      (y.to_f / q).round,
      (z.to_f / q).round
    ].pack("l>3")
  end

  def parse_floats(parts)
    return unless parts && parts.size == 3

    parts.map! { |part| Float(part) }
    parts
  rescue ArgumentError, TypeError
    nil
  end

  def over_vert_cap?(count)
    @budget.max_verts.positive? && count > @budget.max_verts
  end

  def check_limits!
    raise LimitError, @budget.reason || "too_many_verts" if @budget.exhausted?
  end

  def check_time!
    raise LimitError, "time" if @budget.time_exceeded?
  end
end
