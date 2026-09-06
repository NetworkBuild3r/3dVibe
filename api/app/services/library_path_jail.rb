class LibraryPathJail
  def initialize(root)
    @root = Pathname.new(root).expand_path
  end

  def join(folder_name, relative_path)
    folder = normalize_folder(folder_name)
    relative = normalize_relative(relative_path)
    candidate = @root.join(folder, relative).expand_path
    assert_inside!(candidate)
    candidate
  end

  def folder_path(name)
    path = @root.join(normalize_model_folder(name)).expand_path
    assert_inside!(path)
    path
  end

  def normalize_folder(name)
    segment = segments(name).first
    raise ArgumentError, "invalid folder" if segment.blank? || !valid_segment?(segment)

    segment
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
    assert_inside!(dir.expand_path)
    dir
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
end
