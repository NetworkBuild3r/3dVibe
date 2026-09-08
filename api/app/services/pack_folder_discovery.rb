# Lists library-relative pack folders for a scan. INIT-020/SPEC-004
# category_model: Category/Pack (Anime is never a model). flat: first-level.
class PackFolderDiscovery
  COMMON_SUBFOLDERS = %w[
    3mf
    fdm
    files
    images
    lychee
    lys
    model
    obj
    parts
    presupported
    resin
    stl
    sup
    supported
    unsupported
    chitubox
    filesets
  ].freeze

  NFS_STAT_ERRORS = [Errno::ENOENT, Errno::EACCES, Errno::ESTALE].freeze

  def initialize(library, root:, path_prefix: nil)
    @library = library
    @root = Pathname.new(root)
    @path_prefix = path_prefix.to_s.presence
    @jail = LibraryPathJail.new(root)
  end

  def folder_names
    if @path_prefix
      targeted_folders
    elsif flat?
      first_level_folders
    else
      category_pack_folders
    end
  end

  def self.common_subfolder?(name)
    COMMON_SUBFOLDERS.include?(name.to_s.downcase)
  end

  private

  def flat?
    @library.layout_mode == Library::LAYOUT_FLAT
  end

  def targeted_folders
    folder = @jail.normalize_pack_folder(@path_prefix)
    target = @root.join(folder)
    return [] unless jailed_dir?(target)

    if !flat? && pack_segments(folder).size == 1
      packs_under_category(folder)
    else
      [folder]
    end
  rescue ArgumentError
    []
  end

  def first_level_folders
    child_dir_names(@root)
  end

  def category_pack_folders
    names = []
    child_dir_names(@root).each do |category|
      names.concat(packs_under_category(category))
    end
    names.sort
  end

  def packs_under_category(category)
    category_dir = @root.join(category)
    return [] unless jailed_dir?(category_dir)

    names = []
    each_child_name(category_dir) do |name|
      if self.class.common_subfolder?(name)
        Rails.logger.info(
          "[PackFolderDiscovery] skipped common library=#{@library.id} folder=#{category}/#{name}"
        )
        next
      end

      pack = "#{category}/#{name}"
      next unless jailed_dir?(@root.join(pack))

      names << pack
    end
    names.sort
  end

  def child_dir_names(dir)
    names = []
    each_child_name(dir) do |name|
      names << name if jailed_dir?(dir.join(name))
    end
    names.sort
  end

  def each_child_name(dir)
    Dir.each_child(dir.to_s) do |name|
      next if hidden_name?(name)

      yield name
    end
  rescue *NFS_STAT_ERRORS => e
    raise ArgumentError, "Cannot list library root: #{e.message}" if dir == @root

    []
  end

  def hidden_name?(name)
    name.start_with?(".") || LibraryScanner::SKIP_NAMES.include?(name)
  end

  def jailed_dir?(path)
    return false unless File.directory?(path.to_s)

    @jail.assert_realpath_inside!(path)
    true
  rescue ArgumentError, Errno::ENOENT, Errno::ELOOP
    false
  end

  def pack_segments(folder)
    folder.to_s.tr("\\", "/").split("/").reject(&:blank?)
  end
end
