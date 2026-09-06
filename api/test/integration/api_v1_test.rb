require "test_helper"
require "fileutils"
require "zip"

class APIV1Test < ActionDispatch::IntegrationTest
  def setup
    @root = Rails.root.join("tmp/api-library-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(@root.join("signal-horn"))
    File.write(@root.join("signal-horn/horn.stl"), "solid x\nendsolid x\n")
    File.write(@root.join("signal-horn/readme.txt"), "Handheld signal horn.")
    FileUtils.mkdir_p(@root.join("crate"))
    Zip::File.open(@root.join("crate/parts.zip"), Zip::File::CREATE) do |zip|
      zip.get_output_stream("lid.stl") { |io| io.write("solid lid\nendsolid lid\n") }
      zip.get_output_stream("docs/info.txt") { |io| io.write("lid only") }
    end

    @password = "secret123"
    @owner = create_owner!(password: @password)
    @library = Library.create!(name: "Studio", root_path: @root.to_s)
    Membership.create!(user: @owner, library: @library, role: Membership::OWNER)
    LibraryScanner.new(@library).scan!
    @library.curation_proposals.create!(
      kind: "tag",
      summary: "Tag horns as audio",
      payload: { tag: "audio", model_ids: [@library.vibe_models.where(folder_name: "signal-horn").pick(:id)].compact },
      status: CurationProposal::PENDING
    )
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  test "session login and me" do
    post "/api/v1/session", params: { email: @owner.email, password: @password }, as: :json
    assert_response :created
    token = response.parsed_body.fetch("token")

    get "/api/v1/me", headers: { "Authorization" => "Bearer #{token}" }
    assert_response :success
    assert_equal @owner.email, response.parsed_body.dig("user", "email")
  end

  test "rejects unknown credentials" do
    post "/api/v1/session", params: { email: @owner.email, password: "nope" }, as: :json
    assert_response :unauthorized
  end

  test "lists models with cursor pagination and detail plus archive members" do
    headers = auth_header(@owner)

    get "/api/v1/models", params: { limit: 1 }, headers: headers
    assert_response :success
    body = response.parsed_body
    assert_equal 1, body.fetch("models").length
    assert body["next_cursor"].present?

    get "/api/v1/models", params: { cursor: body["next_cursor"], limit: 1 }, headers: headers
    assert_response :success

    model = @library.vibe_models.find_by!(folder_name: "crate")
    get "/api/v1/models/#{model.id}", headers: headers
    assert_response :success
    assert response.parsed_body.dig("model", "assets").any? { |asset| asset["archive"] }

    get "/api/v1/models/#{model.id}/archive_members", headers: headers
    assert_response :success
    paths = response.parsed_body.fetch("members").map { |member| member["internal_path"] }
    assert_includes paths, "lid.stl"
    assert_includes paths, "docs/info.txt"
  end

  test "search uses postgres ilike fallback" do
    get "/api/v1/search", params: { q: "horn" }, headers: auth_header(@owner)
    assert_response :success
    body = response.parsed_body
    titles = body.fetch("models").map { |model| model["title"] }
    assert titles.any? { |title| title.downcase.include?("horn") }
    assert_equal "postgres", body["engine"]
    refute body["fallback"]
    assert body["models"].first.key?("has_preview")
    assert body["facets"]["tags"].present?
  end

  test "search filters by tag and paginates with offset" do
    headers = auth_header(@owner)
    get "/api/v1/search", params: { q: "", tag: "stl", limit: 1 }, headers: headers
    assert_response :success
    body = response.parsed_body
    assert body.fetch("models").all? { |model| model["tags"].include?("stl") }
    assert body["estimated_total"] >= 1

    get "/api/v1/search", params: { q: "lid" }, headers: headers
    assert_response :success
    titles = response.parsed_body.fetch("models").map { |model| model["title"] }
    assert titles.any? { |title| title.downcase.include?("crate") }

    get "/api/v1/search", params: { has_preview: true, limit: 1, offset: 0 }, headers: headers
    assert_response :success
    assert response.parsed_body.fetch("models").all? { |model| model["has_preview"] }
  end

  test "owner can approve and reject curation proposals" do
    headers = auth_header(@owner)
    pending = @library.curation_proposals.pending.first

    post "/api/v1/curation_proposals/#{pending.id}/approve", headers: headers, as: :json
    assert_response :success
    assert_equal "approved", pending.reload.status
    assert pending.applied_at.present?
    horn = @library.vibe_models.find_by!(folder_name: "signal-horn")
    assert_includes horn.tags.reload.map(&:name), "audio"

    other = @library.curation_proposals.create!(kind: "organize", summary: "Shelf", payload: {}, status: "pending")
    post "/api/v1/curation_proposals/#{other.id}/reject", headers: headers, as: :json
    assert_response :success
    assert_equal "rejected", other.reload.status
  end

  test "print bridge queues a mock printer job" do
    model = @library.vibe_models.find_by!(folder_name: "signal-horn")
    asset = model.assets.find_by!(filename: "horn.stl")
    printer = @library.printers.create!(name: "CI mock", host: "127.0.0.1", protocol_type: Printer::MOCK)

    post "/api/v1/print_jobs",
         params: { model_id: model.id, asset_id: asset.id, printer_id: printer.id },
         headers: auth_header(@owner),
         as: :json
    assert_response :accepted
    assert_equal "queued", response.parsed_body.dig("print_job", "status")
    assert_equal printer.id, response.parsed_body.dig("print_job", "printer_id")
  end

  test "friend invite defaults to contributor and can be redeemed" do
    post "/api/v1/invites",
         params: { library_id: @library.id, email: "pal@example.test" },
         headers: auth_header(@owner),
         as: :json
    assert_response :created
    token = response.parsed_body.dig("invite", "token")
    assert_equal Membership::CONTRIBUTOR, response.parsed_body.dig("invite", "role")

    post "/api/v1/invites/#{token}/redeem", params: { password: "friendpass1" }, as: :json
    assert_response :success
    friend = User.find_by!(email: "pal@example.test")
    assert friend.member_of?(@library)
    assert friend.can_upload?(@library)
    assert_equal Membership::CONTRIBUTOR, response.parsed_body.dig("user", "role")
  end

  test "health endpoint does not require auth" do
    get "/up"
    assert_response :success
    assert_equal "3dvibe", response.parsed_body["app"]
  end
end
