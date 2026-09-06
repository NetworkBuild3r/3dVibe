class PrintFileResolver
  def initialize(job)
    @job = job
  end

  def absolute_path
    model = @job.vibe_model
    asset = @job.asset
    library = @job.library || model&.library
    raise ArgumentError, "print job needs a library file" if model.blank? || asset.blank? || library.blank?

    jail = LibraryPathJail.new(library.root_path)
    jail.resolve_file(model.folder_name, asset.relative_path)
  end
end
