class FetchCurationProposalsJob < ApplicationJob
  queue_as :curation

  def perform(library_id = nil)
    errors = []
    scope = library_id.present? ? Library.where(id: library_id) : Library.all
    scope.find_each do |library|
      records = CurationSidecar.new(library).ingest_remote!
      Rails.logger.info("[FetchCurationProposalsJob] library=#{library.id} upserted=#{records.size}")
    rescue CurationHttpClient::Error => e
      Rails.logger.warn("[FetchCurationProposalsJob] library=#{library.id} #{e.message}")
      errors << e
    end
    raise errors.last if errors.any?
  end
end
