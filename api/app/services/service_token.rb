# Shared bearer / X-*-Token check for Rendering and curator ingest.
# Tokens stay separate env vars — this only DRY's the compare.
class ServiceToken
  def self.authorized?(request, env_key:, header:)
    expected = ENV[env_key].to_s
    return false if expected.blank?

    presented = presented_token(request, header: header).to_s
    return false if presented.blank?

    ActiveSupport::SecurityUtils.secure_compare(presented, expected)
  end

  def self.presented_token(request, header:)
    auth = request.headers["Authorization"].to_s
    bearer = auth.split(" ", 2).last if auth.start_with?("Bearer ")
    request.headers[header].presence || bearer
  end
end
