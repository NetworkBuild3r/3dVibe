require "test_helper"
require "fileutils"

class JobsTest < ActiveJob::TestCase
  test "incremental scan job runs the scanner" do
    root = Rails.root.join("tmp/job-lib-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(root.join("only"))
    File.write(root.join("only/a.txt"), "x")
    library = Library.create!(name: "Jobs", root_path: root.to_s)

    IncrementalScanJob.perform_now(library.id)
    assert_equal 1, library.vibe_models.count
  ensure
    FileUtils.rm_rf(root)
  end

  test "preview and apply jobs enqueue without error" do
    user = create_owner!
    library = Library.create!(name: "Jobs", root_path: "/tmp/unused")
    model = library.vibe_models.create!(folder_name: "x", title: "X")
    asset = model.assets.create!(relative_path: "a.stl", filename: "a.stl", kind: "stl")
    pending = library.curation_proposals.create!(kind: "tag", summary: "t", payload: {})
    approved = library.curation_proposals.create!(
      kind: "tag",
      summary: "ready",
      payload: { "model_id" => model.id, "tag" => "job" },
      status: CurationProposal::APPROVED
    )

    assert_nothing_raised do
      DerivePreviewJob.perform_now(asset.id)
      ApplyCurationProposalJob.perform_now(pending.id)
      ApplyCurationProposalJob.perform_now(approved.id)
    end
    refute pending.reload.applied?
    assert approved.reload.applied?
    assert_includes model.tags.reload.map(&:name), "job"
    assert user.present?
  end

  test "fetch job upserts stub proposals" do
    root = Rails.root.join("tmp/fetch-lib-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(root.join("only"))
    File.write(root.join("only/a.txt"), "x")
    library = Library.create!(name: "Fetch", root_path: root.to_s)
    LibraryScanner.new(library).scan!

    FetchCurationProposalsJob.perform_now(library.id)
    assert library.curation_proposals.pending.exists?
  ensure
    FileUtils.rm_rf(root)
  end
end
