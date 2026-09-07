require "test_helper"

class ServiceTokenTest < ActiveSupport::TestCase
  def setup
    @previous = {
      "VIBE_COVER_TOKEN" => ENV["VIBE_COVER_TOKEN"],
      "VIBE_CURATOR_TOKEN" => ENV["VIBE_CURATOR_TOKEN"],
      "VIBE_GEOMETRY_TOKEN" => ENV["VIBE_GEOMETRY_TOKEN"]
    }
    ENV["VIBE_COVER_TOKEN"] = "cover-secret"
    ENV["VIBE_CURATOR_TOKEN"] = "curator-secret"
    ENV["VIBE_GEOMETRY_TOKEN"] = "geometry-secret"
  end

  def teardown
    @previous.each do |key, value|
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end
  end

  test "blank env or blank presented is unauthorized" do
    ENV.delete("VIBE_COVER_TOKEN")
    refute ServiceToken.authorized?(request_with("X-Cover-Token" => "cover-secret"), env_key: "VIBE_COVER_TOKEN", header: "X-Cover-Token")

    ENV["VIBE_COVER_TOKEN"] = "cover-secret"
    refute ServiceToken.authorized?(request_with, env_key: "VIBE_COVER_TOKEN", header: "X-Cover-Token")
  end

  test "custom header or Bearer can match the same env token" do
    assert ServiceToken.authorized?(
      request_with("X-Cover-Token" => "cover-secret"),
      env_key: "VIBE_COVER_TOKEN",
      header: "X-Cover-Token"
    )
    assert ServiceToken.authorized?(
      request_with("Authorization" => "Bearer cover-secret"),
      env_key: "VIBE_COVER_TOKEN",
      header: "X-Cover-Token"
    )
  end

  test "custom header wins over a mismatched Bearer" do
    request = request_with(
      "Authorization" => "Bearer wrong",
      "X-Geometry-Token" => "geometry-secret"
    )
    assert ServiceToken.authorized?(request, env_key: "VIBE_GEOMETRY_TOKEN", header: "X-Geometry-Token")
  end

  test "tokens stay distinct even when the check is shared" do
    cover = request_with("X-Cover-Token" => "cover-secret")
    assert ServiceToken.authorized?(cover, env_key: "VIBE_COVER_TOKEN", header: "X-Cover-Token")
    refute ServiceToken.authorized?(cover, env_key: "VIBE_GEOMETRY_TOKEN", header: "X-Geometry-Token")
    refute ServiceToken.authorized?(cover, env_key: "VIBE_CURATOR_TOKEN", header: "X-Curator-Token")

    refute ServiceToken.authorized?(
      request_with("X-Curator-Token" => "nope"),
      env_key: "VIBE_CURATOR_TOKEN",
      header: "X-Curator-Token"
    )
  end

  private

  def request_with(headers = {})
    request = ActionDispatch::TestRequest.create
    headers.each { |key, value| request.headers[key] = value }
    request
  end
end
