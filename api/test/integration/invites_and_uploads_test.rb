require "test_helper"
require "fileutils"

class InvitesAndUploadsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  def setup
    @root = Rails.root.join("tmp/shared-lib-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(@root.join("signal-horn"))
    File.write(@root.join("signal-horn/horn.stl"), "solid x\nendsolid x\n")

    @password = "secret123"
    @owner = create_owner!(password: @password)
    @library = Library.create!(name: "Shared pile", root_path: @root.to_s)
    Membership.create!(user: @owner, library: @library, role: Membership::OWNER)
    LibraryScanner.new(@library).scan!
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  test "owner can create a link invite with role and expiry then revoke it" do
    post "/api/v1/invites",
         params: { library_id: @library.id, role: Membership::VIEWER, expires_in_days: 2 },
         headers: auth_header(@owner),
         as: :json
    assert_response :created

    invite = response.parsed_body.fetch("invite")
    assert_nil invite["email"]
    assert_equal Membership::VIEWER, invite["role"]
    assert invite["pending"]
    assert invite["token"].present?
    assert_equal "/invite/#{invite['token']}", invite["redeem_path"]
    assert invite["expires_at"].present?

    get "/api/v1/invites/token/#{invite['token']}", as: :json
    assert_response :success
    assert_equal "Shared pile", response.parsed_body.dig("invite", "library_name")
    assert_nil response.parsed_body.dig("invite", "token")

    post "/api/v1/invites/#{invite['id']}/revoke", headers: auth_header(@owner), as: :json
    assert_response :success
    refute response.parsed_body.dig("invite", "pending")

    post "/api/v1/invites/#{invite['token']}/redeem",
         params: { email: "late@example.test", password: "viewerpass1", display_name: "Late" },
         as: :json
    assert_response :conflict
  end

  test "link invite redeem signs the new user in as a contributor" do
    post "/api/v1/invites",
         params: { library_id: @library.id },
         headers: auth_header(@owner),
         as: :json
    token = response.parsed_body.dig("invite", "token")

    post "/api/v1/invites/#{token}/redeem",
         params: { email: "pal@example.test", password: "friendpass1", display_name: "Pal" },
         as: :json
    assert_response :success
    body = response.parsed_body
    assert body["token"].present?
    assert_equal "pal@example.test", body.dig("user", "email")
    assert_equal Membership::CONTRIBUTOR, body.dig("user", "role")
    assert body.dig("user", "can_upload")
    assert body.dig("user", "can_curate")
    refute body.dig("user", "can_invite")

    get "/api/v1/me", headers: { "Authorization" => "Bearer #{body['token']}" }
    assert_response :success
    assert_equal "Pal", response.parsed_body.dig("user", "display_name")
  end

  test "contributor cannot create invites and viewer cannot upload" do
    contributor = create_user!(email: "contrib@example.test")
    viewer = create_user!(email: "viewer@example.test")
    Membership.create!(user: contributor, library: @library, role: Membership::CONTRIBUTOR)
    Membership.create!(user: viewer, library: @library, role: Membership::VIEWER)

    post "/api/v1/invites",
         params: { library_id: @library.id, email: "nope@example.test" },
         headers: auth_header(contributor),
         as: :json
    assert_response :forbidden

    post "/api/v1/uploads",
         params: { library_id: @library.id, folder_name: "blocked", filename: "x.stl", byte_size: 4 },
         headers: auth_header(viewer),
         as: :json
    assert_response :forbidden
    refute File.exist?(@root.join("blocked/x.stl"))
  end

  test "all signed-in roles see the whole catalog with no owner ACL filter" do
    viewer = create_user!(email: "viewer@example.test")
    Membership.create!(user: viewer, library: @library, role: Membership::VIEWER)

    get "/api/v1/models", headers: auth_header(viewer)
    assert_response :success
    titles = response.parsed_body.fetch("models").map { |model| model["title"] }
    assert_includes titles, "Signal Horn"
    assert response.parsed_body.fetch("models").none? { |model| model.key?("private") }
  end

  test "contributor chunked upload lands in the library and appears for every user after scan" do
    contributor = create_user!(email: "contrib@example.test")
    viewer = create_user!(email: "viewer@example.test")
    Membership.create!(user: contributor, library: @library, role: Membership::CONTRIBUTOR)
    Membership.create!(user: viewer, library: @library, role: Membership::VIEWER)

    payload = "solid uploaded\nendsolid uploaded\n"
    perform_enqueued_jobs only: IncrementalScanJob do
      post "/api/v1/uploads",
           params: {
             library_id: @library.id,
             folder_name: "friend-dragon",
             relative_path: "dragon.stl",
             filename: "dragon.stl",
             byte_size: payload.bytesize
           },
           headers: auth_header(contributor),
           as: :json
      assert_response :created
      upload_id = response.parsed_body.dig("upload", "id")

      first = payload.byteslice(0, 8)
      rest = payload.byteslice(8, payload.bytesize)

      patch "/api/v1/uploads/#{upload_id}",
            params: { offset: 0, chunk_b64: Base64.strict_encode64(first) },
            headers: auth_header(contributor),
            as: :json
      assert_response :success
      assert_equal first.bytesize, response.parsed_body.dig("upload", "byte_offset")

      patch "/api/v1/uploads/#{upload_id}",
            params: { offset: first.bytesize, chunk_b64: Base64.strict_encode64(rest) },
            headers: auth_header(contributor),
            as: :json
      assert_response :success
      assert_equal "completed", response.parsed_body.dig("upload", "status")
    end

    assert File.file?(@root.join("friend-dragon/dragon.stl"))
    assert_equal payload, File.read(@root.join("friend-dragon/dragon.stl"))
    incoming = @root.join(".vibe-incoming")
    assert Dir.glob(incoming.join("*")).empty? if incoming.directory?

    model = @library.vibe_models.find_by!(folder_name: "friend-dragon")
    assert_equal contributor.id, model.uploaded_by_id
    assert_equal contributor.id, model.assets.find_by!(filename: "dragon.stl").uploaded_by_id

    get "/api/v1/models", headers: auth_header(viewer)
    assert_response :success
    uploaded = response.parsed_body.fetch("models").find { |item| item["folder_name"] == "friend-dragon" }
    assert uploaded
    assert_equal "Friend Dragon", uploaded["title"]
    assert_equal contributor.display_name, uploaded.dig("uploaded_by", "display_name")
  end

  test "direct upload rejects path traversal and leaves the library jail intact" do
    contributor = create_user!(email: "contrib@example.test")
    Membership.create!(user: contributor, library: @library, role: Membership::CONTRIBUTOR)
    source = @root.join("source-escape.stl")
    File.write(source, "solid escape\nendsolid escape\n")

    post "/api/v1/uploads/direct",
         params: {
           library_id: @library.id,
           folder_name: "../outside",
           relative_path: "escape.stl",
           file: Rack::Test::UploadedFile.new(source.to_s, "model/stl", false, original_filename: "escape.stl")
         },
         headers: auth_header(contributor)
    assert_response :unprocessable_entity
    refute File.exist?(Rails.root.join("tmp/outside/escape.stl"))

    post "/api/v1/uploads/direct",
         params: {
           library_id: @library.id,
           folder_name: "safe-folder",
           relative_path: "../../escape.stl",
           file: Rack::Test::UploadedFile.new(source.to_s, "model/stl", false, original_filename: "escape.stl")
         },
         headers: auth_header(contributor)
    assert_response :unprocessable_entity
    refute File.exist?(@root.join("escape.stl"))
  end

  test "owner lists invites" do
    @library.invites.create!(invited_by: @owner, email: "one@example.test", role: Membership::CONTRIBUTOR)
    get "/api/v1/invites", headers: auth_header(@owner)
    assert_response :success
    assert response.parsed_body.fetch("invites").length >= 1
  end
end
