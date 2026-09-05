class IncrementalScanJob < ApplicationJob
  queue_as :scan

  def perform(library_id)
    library = Library.find(library_id)
    LibraryScanner.new(library).scan!
  end
end
