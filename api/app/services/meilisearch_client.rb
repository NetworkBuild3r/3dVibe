require "json"
require "net/http"
require "uri"

# Thin Meilisearch HTTP client. Search and index calls fail soft so Postgres
# can take over when the sidecar is down (dev/CI).
class MeilisearchClient
  class Error < StandardError; end

  INDEX_UID = "vibe_models"
  DEFAULT_TIMEOUT = 2.0

  def self.url
    ENV["MEILI_URL"].presence || ENV["MEILISEARCH_URL"].presence
  end

  def self.master_key
    ENV["MEILI_MASTER_KEY"].presence
  end

  def self.search_key
    ENV["MEILI_SEARCH_KEY"].presence || master_key
  end

  def self.configured?
    url.present?
  end

  def initialize(endpoint: self.class.url, master_key: self.class.master_key, search_key: self.class.search_key, timeout: nil)
    @endpoint = endpoint.to_s.strip.chomp("/")
    @master_key = master_key.to_s.presence
    @search_key = search_key.to_s.presence || @master_key
    @timeout = (timeout.presence || ENV.fetch("MEILI_TIMEOUT", DEFAULT_TIMEOUT)).to_f
  end

  def configured?
    @endpoint.present?
  end

  def available?
    return false unless configured?

    response = request(:get, "/health", key: nil)
    response.code.to_i.between?(200, 299)
  rescue Error, Timeout::Error, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError
    false
  end

  def ensure_index!
    create = request(:post, "/indexes", body: { uid: INDEX_UID, primaryKey: "id" }, key: @master_key)
    unless [200, 201, 202, 409].include?(create.code.to_i)
      raise Error, "create index HTTP #{create.code}: #{create.body.to_s.truncate(200)}"
    end

    settings = request(:patch, "/indexes/#{INDEX_UID}/settings", body: index_settings, key: @master_key)
    unless settings.code.to_i.between?(200, 299)
      raise Error, "index settings HTTP #{settings.code}: #{settings.body.to_s.truncate(200)}"
    end

    true
  end

  def upsert_documents(documents)
    return if documents.blank?

    response = request(:put, "/indexes/#{INDEX_UID}/documents", body: Array(documents), key: @master_key)
    unless response.code.to_i.between?(200, 299)
      raise Error, "upsert HTTP #{response.code}: #{response.body.to_s.truncate(200)}"
    end

    parse_json(response.body)
  end

  def delete_document(id)
    response = request(:delete, "/indexes/#{INDEX_UID}/documents/#{id}", key: @master_key)
    return if [200, 202, 204, 404].include?(response.code.to_i)

    raise Error, "delete HTTP #{response.code}: #{response.body.to_s.truncate(200)}"
  end

  def search(query, filter: nil, offset: 0, limit: 24, facets: [])
    payload = {
      q: query.to_s,
      offset: offset.to_i,
      limit: limit.to_i,
      showRankingScore: false
    }
    payload[:filter] = filter if filter.present?
    payload[:facets] = facets if facets.present?

    response = request(:post, "/indexes/#{INDEX_UID}/search", body: payload, key: @search_key)
    unless response.code.to_i.between?(200, 299)
      raise Error, "search HTTP #{response.code}: #{response.body.to_s.truncate(200)}"
    end

    parse_json(response.body)
  end

  private

  def index_settings
    {
      searchableAttributes: %w[name title folder_name path synopsis tags filenames asset_paths archive_paths uploader],
      filterableAttributes: %w[tags has_preview library_id uploaded_by_id kinds],
      sortableAttributes: %w[updated_at],
      displayedAttributes: %w[id]
    }
  end

  def request(method, path, body: nil, key: nil)
    raise Error, "MEILI_URL is blank" if @endpoint.blank?

    uri = URI.parse("#{@endpoint}#{path}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = @timeout
    http.read_timeout = @timeout
    http.write_timeout = @timeout if http.respond_to?(:write_timeout=)

    klass = { get: Net::HTTP::Get, post: Net::HTTP::Post, put: Net::HTTP::Put, patch: Net::HTTP::Patch, delete: Net::HTTP::Delete }.fetch(method)
    request = klass.new(uri.request_uri)
    request["Accept"] = "application/json"
    request["Authorization"] = "Bearer #{key}" if key.present?
    if body
      request["Content-Type"] = "application/json"
      request.body = JSON.generate(body)
    end
    http.request(request)
  rescue Timeout::Error, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError => e
    raise Error, "meilisearch unreachable: #{e.message}"
  end

  def parse_json(body)
    JSON.parse(body.presence || "{}")
  rescue JSON::ParserError => e
    raise Error, "meilisearch returned invalid JSON: #{e.message}"
  end
end
