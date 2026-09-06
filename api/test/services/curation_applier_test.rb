require "test_helper"
require "fileutils"

class CurationApplierTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def setup
    @root = Rails.root.join("tmp/curate-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(@root.join("signal-horn"))
    File.write(@root.join("signal-horn/horn.stl"), "solid horn\nendsolid horn\n")
    File.write(@root.join("signal-horn/readme.txt"), "horn")
    FileUtils.mkdir_p(@root.join("hex-tray"))
    File.write(@root.join("hex-tray/hex.stl"), "solid hex\nendsolid hex\n")
    File.write(@root.join("hex-tray/readme.txt"), "tray")

    @library = Library.create!(name: "Curate", root_path: @root.to_s)
    LibraryScanner.new(@library).scan!
    @horn = @library.vibe_models.find_by!(folder_name: "signal-horn")
    @tray = @library.vibe_models.find_by!(folder_name: "hex-tray")
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  test "applies tags without touching disk" do
    proposal = approve("tag", { "model_id" => @horn.id, "tag" => "audio" })

    CurationApplier.new(proposal).apply!

    assert_includes @horn.tags.reload.map(&:name), "audio"
    assert proposal.reload.applied?
    assert_nil proposal.apply_error
    assert File.exist?(@root.join("signal-horn/horn.stl"))
  end

  test "renames a model folder inside the path jail and enqueues a targeted scan" do
    proposal = approve("rename", { "model_id" => @horn.id, "to" => "signal-horn-curated", "title" => "Signal Horn Curated" })

    assert_enqueued_jobs 2, only: IncrementalScanJob do
      CurationApplier.new(proposal).apply!
    end
    prefixes = enqueued_jobs.select { |job| job[:job] == IncrementalScanJob }.flat_map { |job| job[:args] }
    assert_includes prefixes, "signal-horn-curated"
    assert_includes prefixes, "signal-horn"

    assert proposal.reload.applied?
    assert_equal "signal-horn-curated", @horn.reload.folder_name
    assert_equal "Signal Horn Curated", @horn.title
    assert File.directory?(@root.join("signal-horn-curated"))
    refute File.directory?(@root.join("signal-horn"))
    assert File.exist?(@root.join("signal-horn-curated/horn.stl"))
  end

  test "rejects rename destinations that escape the library root" do
    proposal = approve("rename", { "model_id" => @horn.id, "to" => "../escape" })

    CurationApplier.new(proposal).apply!

    refute proposal.reload.applied?
    assert_match(/first-level|invalid folder/i, proposal.apply_error)
    assert File.directory?(@root.join("signal-horn"))
    refute File.exist?(@root.join("../escape"))
  end

  test "rejects hidden and nested rename destinations" do
    hidden = approve("rename", { "folder_name" => "signal-horn", "to" => ".hidden" })
    CurationApplier.new(hidden).apply!
    refute hidden.reload.applied?
    assert File.directory?(@root.join("signal-horn"))

    nested = approve("move", { "model_id" => @horn.id, "to" => "kits/horn" })
    CurationApplier.new(nested).apply!
    refute nested.reload.applied?
    assert_match(/first-level/i, nested.apply_error)
  end

  test "merges by moving files and only removes the empty source directory" do
    leftover_root = @root.join("hex-tray")
    proposal = approve("merge", {
      "source_id" => @tray.id,
      "target_id" => @horn.id,
      "from" => "hex-tray",
      "to" => "signal-horn"
    })

    CurationApplier.new(proposal).apply!

    assert proposal.reload.applied?
    assert proposal.result["source_removed"]
    assert File.exist?(@root.join("signal-horn/hex-tray/hex.stl"))
    assert File.exist?(@root.join("signal-horn/hex-tray/readme.txt"))
    assert File.exist?(@root.join("signal-horn/horn.stl"))
    refute File.directory?(leftover_root)
    refute @library.vibe_models.exists?(id: @tray.id)
  end

  test "does not apply rejected or pending proposals" do
    pending = @library.curation_proposals.create!(kind: "tag", summary: "no", payload: { "tag" => "x", "model_id" => @horn.id })
    CurationApplier.new(pending).apply!
    refute pending.reload.applied?
    assert_equal "not_approved", pending.apply_error
    refute_includes @horn.tags.reload.map(&:name), "x"
  end

  test "organize with a shelf only assigns tags" do
    proposal = approve("organize", { "shelf" => "kits", "model_ids" => [@horn.id, @tray.id] })
    CurationApplier.new(proposal).apply!
    assert_includes @horn.tags.reload.map(&:name), "kits"
    assert_includes @tray.tags.reload.map(&:name), "kits"
    assert File.directory?(@root.join("signal-horn"))
  end

  private

  def approve(kind, payload)
    @library.curation_proposals.create!(
      kind: kind,
      summary: "#{kind} test",
      payload: payload,
      status: CurationProposal::APPROVED,
      reviewed_at: Time.current
    )
  end
end
