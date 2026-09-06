class FetchCurationProposalsJob < ApplicationJob
  queue_as :curation

  def perform(library_id = nil)
    scope = library_id.present? ? Library.where(id: library_id) : Library.all
    scope.find_each do |library|
      records = CurationSidecar.new(library).ingest_remote!
      Rails.logger.info("[FetchCurationProposalsJob] library=#{library.id} upserted=#{records.size}")
    end
  rescue CurationHttpClient::Error => e
    Rails.logger.warn("[FetchCurationProposalsJob] #{e.message}")
    raise
  end
end
