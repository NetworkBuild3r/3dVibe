require "json"
require "net/http"
require "uri"

# HTTP client for an external curation sidecar (Spark later, stub now).
# Rails polls + upserts; inference stays in Rendering adapters.
class CurationHttpClient
  class Error < StandardError; end

  def initialize(endpoint:, token: ENV["VIBE_CURATOR_TOKEN"], timeout: nil)
    @endpoint = endpoint.to_s.strip.chomp("/")
    @token = token.to_s.presence
    @timeout = (timeout.presence || ENV.fetch("VIBE_CURATOR_TIMEOUT", "8")).to_f
  end

  def fetch_proposals(catalog)
    raise Error, "VIBE_CURATOR_URL is blank" if @endpoint.blank?

    response = post_proposals(catalog)
    if response && [404, 405].include?(response.code.to_i)
      response = get_proposals(catalog)
    end
    raise Error, "curator did not respond" if response.nil?
    unless response.code.to_i.between?(200, 299)
      raise Error, "curator HTTP #{response.code}: #{response.body.to_s.truncate(240)}"
    end

    parsed = parse_json(response.body)
    CurationSidecar::FetchResult.new(
      drafts: drafts_from(parsed),
      provider: extract_provider(response, parsed)
    )
  rescue Timeout::Error, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError => e
    raise Error, "curator unreachable: #{e.message}"
  end

  private

  def post_proposals(catalog)
    request = Net::HTTP::Post.new(proposals_uri.request_uri)
    apply_headers(request)
    request["Content-Type"] = "application/json"
    request.body = catalog.to_json
    perform(request)
  end

  def get_proposals(catalog)
    uri = proposals_uri
    query = URI.decode_www_form(uri.query || "")
    query << ["library_id", catalog[:library_id].to_s] if catalog[:library_id]
    query << ["library_root", catalog[:library_root].to_s] if catalog[:library_root]
    query << ["provider_hint", catalog[:provider_hint].to_s] if catalog[:provider_hint]
    uri.query = URI.encode_www_form(query)
    request = Net::HTTP::Get.new(uri.request_uri)
    apply_headers(request)
    perform(request, uri)
  end

  def apply_headers(request)
    request["Accept"] = "application/json"
    request["Authorization"] = "Bearer #{@token}" if @token
    request["X-Curator-Token"] = @token if @token
  end

  def perform(request, uri = proposals_uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = @timeout
    http.read_timeout = @timeout
    http.write_timeout = @timeout if http.respond_to?(:write_timeout=)
    http.request(request)
  end

  def proposals_uri
    URI.parse("#{@endpoint}/proposals")
  end

  def parse_json(body)
    JSON.parse(body.presence || "{}")
  rescue JSON::ParserError => e
    raise Error, "curator returned invalid JSON: #{e.message}"
  end

  def drafts_from(parsed)
    items = parsed.is_a?(Hash) ? (parsed["proposals"] || parsed["drafts"] || []) : []
    Array(items).map { |item| draft_from(item) }
  end

  def extract_provider(response, parsed)
    header = response["X-Curator-Provider"].presence || response["X-Provider"].presence
    body = parsed.is_a?(Hash) ? (parsed["provider"].presence || parsed["provider_hint"].presence) : nil
    header || body
  end

  def draft_from(item)
    data = item.stringify_keys
    CurationSidecar::ProposalDraft.new(
      kind: data["kind"],
      summary: data["summary"],
      payload: (data["payload"].presence || {}).stringify_keys,
      sidecar_ref: data["sidecar_ref"]
    )
  end
end
