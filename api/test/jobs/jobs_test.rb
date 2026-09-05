require "test_helper"

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

  test "preview and apply stubs enqueue without error" do
    user = create_owner!
    library = Library.create!(name: "Jobs", root_path: "/tmp/unused")
    model = library.vibe_models.create!(folder_name: "x", title: "X")
    asset = model.assets.create!(relative_path: "a.stl", filename: "a.stl", kind: "stl")
    proposal = library.curation_proposals.create!(kind: "tag", summary: "t", payload: {})

    assert_nothing_raised do
      DerivePreviewJob.perform_now(asset.id)
      ApplyCurationProposalJob.perform_now(proposal.id)
    end
    assert user.present?
  end
end
