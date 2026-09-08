require "find"

class LibraryPathJail
  def initialize(root)
    @root = Pathname.new(root).expand_path
  end

  # Regular files only. Directory (and file) symlinks are not followed, so a
  # nested escape hatch cannot walk or move bytes from outside the jail.
  def self.each_regular_file(dir)
    root = Pathname.new(dir)
    Find.find(root.to_s) do |path|
      pathname = Pathname.new(path)
      if pathname.symlink?
        Find.prune
        next
      end
      next unless pathname.file?

      yield pathname, pathname.relative_path_from(root).to_s
    end
  end

  def self.remove_empty_tree!(dir, junk_names: [])
    dir = Pathname.new(dir)
    return false unless dir.directory? && !dir.symlink?

    dir.children.each do |child|
      next if child.symlink?

      if child.directory?
        remove_empty_tree!(child, junk_names: junk_names)
      elsif junk_names.include?(child.basename.to_s)
        child.unlink
      end
    end
    return false unless dir.empty?

    dir.rmdir
    true
  rescue Errno::ENOTEMPTY, Errno::ENOENT
    false
  end

  def join(folder_name, relative_path)
    folder = normalize_pack_folder(folder_name)
    relative = normalize_relative(relative_path)
    candidate = @root.join(folder, relative).expand_path
    assert_inside!(candidate)
    assert_physical_inside!(candidate)
    candidate
  end

  # Pack leaf (flat or Category/Pack). INIT-020/SPEC-005.
  def folder_path(name)
    path = @root.join(normalize_pack_folder(name)).expand_path
    assert_inside!(path)
    assert_physical_inside!(path)
    path
  end

  def normalize_folder(name)
    segment = segments(name).first
    raise ArgumentError, "invalid folder" if segment.blank? || !valid_segment?(segment)

    segment
  end

  # Scan / asset identity: first-level (flat) or Category/Pack. INIT-020/SPEC-004
  def normalize_pack_folder(name)
    parts = segments(name)
    raise ArgumentError, "invalid folder" if parts.empty? || parts.size > 2
    raise ArgumentError, "invalid folder" unless parts.all? { |part| valid_segment?(part) }

    parts.join("/")
  end

  # Vibe models are first-level folders. Rename/move must stay there.
  def normalize_model_folder(name)
    parts = segments(name)
    raise ArgumentError, "rename/move must stay a first-level library folder" if parts.size != 1

    normalize_folder(name)
  end

  def normalize_relative(path)
    parts = segments(path)
    raise ArgumentError, "empty path" if parts.empty?
    raise ArgumentError, "invalid path" unless parts.all? { |part| valid_segment?(part) }

    parts.join("/")
  end

  def incoming_dir
    dir = @root.join(".vibe-incoming")
    expanded = dir.expand_path
    assert_inside!(expanded)
    assert_physical_inside!(expanded)
    dir
  end

  # Jail-relative path from the library root, e.g. "CreatorPack/model/preview.png".
  def resolve_jailed(jailed_path)
    parts = segments(jailed_path)
    raise ArgumentError, "empty path" if parts.empty?
    raise ArgumentError, "jailed path must include a file under a model folder" if parts.size < 2

    resolve_file(parts.first, parts[1..].join("/"))
  end

  # Resolve a regular file under the library root. Used by the print bridge so
  # workers never read a path the browser (or a stale Asset row) pointed outside.
  def resolve_file(folder_name, relative_path)
    path = join(folder_name, relative_path)
    raise ArgumentError, "print file is not in the library" unless File.file?(path.to_s)

    real = path.realpath
    assert_inside!(real)
    real
  end

  def assert_realpath_inside!(candidate)
    real = strict_realpath(candidate)
    assert_inside!(real)
    real
  end

  private

  def segments(value)
    value.to_s.tr("\\", "/").split("/").reject(&:blank?)
  end

  def valid_segment?(part)
    part.present? && part != "." && part != ".." && !part.include?("\0") && !part.start_with?(".")
  end

  def assert_inside!(candidate)
    root = @root.to_s
    path = candidate.to_s
    return if path == root || path.start_with?(root + File::SEPARATOR)

    raise ArgumentError, "path escapes library root"
  end

  # Lexical join is not enough: a first-level folder or dest file can be a
  # symlink that FileUtils.cp / mv / open will follow out of the jail.
  def assert_physical_inside!(candidate)
    path = Pathname.new(candidate)
    if path.symlink? || path.exist?
      assert_inside!(strict_realpath(path))
      return
    end

    parent = path.parent
    while parent != @root && !parent.root?
      if parent.symlink? || parent.exist?
        assert_inside!(strict_realpath(parent))
        return
      end
      parent = parent.parent
    end
  end

  def strict_realpath(path)
    Pathname.new(path).realpath
  rescue Errno::ENOENT, Errno::ELOOP
    raise ArgumentError, "path escapes library root"
  end
end
