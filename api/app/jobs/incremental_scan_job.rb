class IncrementalScanJob < ApplicationJob
  queue_as :scan

  def perform(library_id, path_prefix = nil, uploaded_by_id = nil)
    library = Library.find(library_id)
    uploaded_by = User.find_by(id: uploaded_by_id) if uploaded_by_id
    LibraryScanner.new(library, uploaded_by: uploaded_by).scan!(path_prefix: path_prefix)
  end
end
