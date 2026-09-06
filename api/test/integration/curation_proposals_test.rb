require "test_helper"
require "fileutils"

class CurationProposalsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  def setup
    @root = Rails.root.join("tmp/curation-api-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(@root.join("signal-horn"))
    File.write(@root.join("signal-horn/horn.stl"), "solid x\nendsolid x\n")
    FileUtils.mkdir_p(@root.join("hex-tray"))
    File.write(@root.join("hex-tray/hex.stl"), "solid y\nendsolid y\n")

    @owner = create_owner!
    @library = Library.create!(name: "Studio", root_path: @root.to_s)
    Membership.create!(user: @owner, library: @library, role: Membership::OWNER)
    LibraryScanner.new(@library).scan!
    @horn = @library.vibe_models.find_by!(folder_name: "signal-horn")

    @contributor = create_user!(email: "contrib@example.test")
    Membership.create!(user: @contributor, library: @library, role: Membership::CONTRIBUTOR)
    @viewer = create_user!(email: "viewer@example.test")
    Membership.create!(user: @viewer, library: @library, role: Membership::VIEWER)
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  test "owner fetch from stub curator upserts pending proposals" do
    @library.update!(last_error: "stale", last_polled_at: 1.day.ago)
    post "/api/v1/curation_proposals/fetch",
         params: { library_id: @library.id },
         headers: auth_header(@owner),
         as: :json
    assert_response :success
    proposals = response.parsed_body.fetch("proposals")
    assert proposals.size >= 3
    assert proposals.all? { |item| item["status"] == "pending" }
    assert proposals.any? { |item| item["preview"].is_a?(Hash) }
    assert proposals.any? { |item| item.dig("preview", "before", "folder_name").present? }
    curation = response.parsed_body.fetch("curation")
    assert_nil curation["last_error"]
    assert_equal "stub", curation["last_provider"]
    assert curation["last_polled_at"].present?

    get "/api/v1/curation_proposals", headers: auth_header(@owner)
    assert_response :success
    row = response.parsed_body.fetch("libraries").find { |item| item["id"] == @library.id }
    assert_equal "stub", row.dig("curation", "last_provider")
    assert_nil row.dig("curation", "last_error")
  end

  test "contributor can approve a tag immediately and viewer cannot" do
    proposal = @library.curation_proposals.create!(
      kind: "tag",
      summary: "Tag horn",
      payload: { "model_id" => @horn.id, "tag" => "audio" },
      status: CurationProposal::PENDING
    )

    post "/api/v1/curation_proposals/#{proposal.id}/approve", headers: auth_header(@viewer), as: :json
    assert_response :forbidden
    assert_equal "pending", proposal.reload.status

    post "/api/v1/curation_proposals/#{proposal.id}/approve", headers: auth_header(@contributor), as: :json
    assert_response :success
    body = response.parsed_body.fetch("proposal")
    assert_equal "approved", body["status"]
    assert body["applied_at"].present?
    assert_includes @horn.tags.reload.map(&:name), "audio"
  end

  test "approve rename enqueues apply plus incremental scan and stays in jail" do
    proposal = @library.curation_proposals.create!(
      kind: "rename",
      summary: "Rename horn",
      payload: { "model_id" => @horn.id, "to" => "signal-horn-curated" },
      status: CurationProposal::PENDING
    )

    assert_enqueued_with(job: ApplyCurationProposalJob, args: [proposal.id]) do
      post "/api/v1/curation_proposals/#{proposal.id}/approve", headers: auth_header(@owner), as: :json
      assert_response :success
    end

    perform_enqueued_jobs
    assert File.directory?(@root.join("signal-horn-curated"))
    assert_equal "signal-horn-curated", @horn.reload.folder_name
    assert proposal.reload.applied?
  end

  test "bulk reject and approve" do
    one = @library.curation_proposals.create!(kind: "tag", summary: "A", payload: { "tag" => "one", "model_id" => @horn.id })
    two = @library.curation_proposals.create!(kind: "tag", summary: "B", payload: { "tag" => "two", "model_id" => @horn.id })

    post "/api/v1/curation_proposals/bulk",
         params: { ids: [one.id, two.id], decision: "reject" },
         headers: auth_header(@owner),
         as: :json
    assert_response :success
    assert_equal "rejected", one.reload.status
    assert_equal "rejected", two.reload.status

    three = @library.curation_proposals.create!(kind: "tag", summary: "C", payload: { "tags" => ["bulk"], "model_id" => @horn.id })
    post "/api/v1/curation_proposals/bulk",
         params: { ids: [three.id], decision: "approve" },
         headers: auth_header(@owner),
         as: :json
    assert_response :success
    assert_equal "approved", three.reload.status
    assert_includes @horn.tags.reload.map(&:name), "bulk"
  end

  test "ingest webhook upserts with curator token" do
    ENV["VIBE_CURATOR_TOKEN"] = "test-curator-token"
    post "/api/v1/curation_proposals/ingest",
         params: {
           library_id: @library.id,
           proposals: [
             {
               kind: "tag",
               summary: "Webhook tag",
               sidecar_ref: "hook:tag:1",
               payload: { tag: "webhook", model_id: @horn.id }
             }
           ]
         },
         headers: { "X-Curator-Token" => "test-curator-token" },
         as: :json
    assert_response :created
    record = @library.curation_proposals.find_by!(sidecar_ref: "hook:tag:1")
    assert_equal "Webhook tag", record.summary
  ensure
    ENV.delete("VIBE_CURATOR_TOKEN")
  end

  test "me reports can_curate for contributors" do
    get "/api/v1/me", headers: auth_header(@contributor)
    assert_response :success
    assert response.parsed_body.dig("user", "can_curate")

    get "/api/v1/me", headers: auth_header(@viewer)
    assert_response :success
    refute response.parsed_body.dig("user", "can_curate")
  end

  test "me and library detail expose curation poll state" do
    @library.update!(
      last_polled_at: Time.utc(2026, 9, 6, 12, 0, 0),
      last_provider: "ollama",
      last_error: nil
    )

    get "/api/v1/me", headers: auth_header(@owner)
    assert_response :success
    row = response.parsed_body.fetch("user").fetch("libraries").find { |item| item["id"] == @library.id }
    assert_equal "ollama", row.dig("curation", "last_provider")
    assert row.dig("curation", "last_polled_at").present?
    assert_nil row.dig("curation", "last_error")

    get "/api/v1/libraries/#{@library.id}", headers: auth_header(@owner)
    assert_response :success
    curation = response.parsed_body.fetch("library").fetch("curation")
    assert_equal "ollama", curation["last_provider"]
    assert_nil curation["last_error"]
  end
end
