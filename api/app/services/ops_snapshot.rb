# Read-only library ops chip payload. Cheap SQL counts only — never walks NFS,
# never deletes, never enqueues jobs.
class OpsSnapshot
  def initialize(library, meili: nil)
    @library = library
    @meili = meili
  end

  def as_api
    {
      library_id: @library.id,
      library_name: @library.name,
      scan: @library.scan_as_api,
      curator: @library.curation_as_api,
      covers: @library.cover_backlog_as_api,
      geometry: @library.geometry_backlog_as_api,
      meili: meili_health
    }
  end

  def self.meili_health(client = MeilisearchClient.new)
    client.health
  end

  private

  def meili_health
    return @meili if @meili.is_a?(Hash)

    (@meili || MeilisearchClient.new).health
  end
end
