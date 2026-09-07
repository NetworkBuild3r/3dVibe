require "test_helper"

# Pins the in-process CI stub (VIBE_CURATOR_URL=stub). Refs/kinds/payloads
# must stay aligned with curator/test/stub_contract_test.rb. The two
# generators are process-isolated on purpose — see CurationStubProposals.
class CurationStubProposalsTest < ActiveSupport::TestCase
  def setup
    @library = Library.create!(name: "Stub contract", root_path: "/tmp/unused-stub-contract")
    @alpha = @library.vibe_models.create!(folder_name: "alpha-one", title: "Alpha One")
    @beta = @library.vibe_models.create!(folder_name: "beta-two", title: "Beta Two")
  end

  test "empty catalog emits no drafts" do
    assert_empty CurationStubProposals.new(@library, models: []).drafts
  end

  test "emits deterministic kinds and stub refs for a two-model catalog" do
    drafts = CurationStubProposals.new(@library).drafts

    assert_equal %w[tag rename move merge organize], drafts.map(&:kind)
    assert_equal(
      [
        "stub:tag:alpha-one",
        "stub:rename:alpha-one",
        "stub:move:beta-two",
        "stub:merge:alpha-one:beta-two",
        "stub:organize:fixture"
      ],
      drafts.map(&:sidecar_ref)
    )
    assert_equal drafts.map(&:sidecar_ref).uniq, drafts.map(&:sidecar_ref)
  end

  test "payloads stay the HITL fixture shape" do
    drafts = CurationStubProposals.new(@library).drafts
    by_kind = drafts.index_by(&:kind)

    assert_equal(
      { "model_id" => @alpha.id, "folder_name" => "alpha-one", "tag" => "alpha", "tags" => ["alpha"] },
      by_kind["tag"].payload
    )
    assert_equal "Tag Alpha One as alpha", by_kind["tag"].summary

    assert_equal(
      {
        "model_id" => @alpha.id,
        "folder_name" => "alpha-one",
        "to" => "alpha-one-curated",
        "title" => "Alpha One Curated"
      },
      by_kind["rename"].payload
    )
    assert_equal "Rename alpha-one → alpha-one-curated", by_kind["rename"].summary

    assert_equal(
      { "model_id" => @beta.id, "from" => "beta-two", "to" => "beta-two-shelf" },
      by_kind["move"].payload
    )
    assert_equal "Move beta-two → beta-two-shelf", by_kind["move"].summary

    assert_equal(
      {
        "source_id" => @alpha.id,
        "target_id" => @beta.id,
        "left_id" => @alpha.id,
        "right_id" => @beta.id,
        "from" => "alpha-one",
        "to" => "beta-two"
      },
      by_kind["merge"].payload
    )
    assert_equal "Merge alpha-one into beta-two", by_kind["merge"].summary

    assert_equal(
      {
        "shelf" => "fixture",
        "folder_names" => %w[alpha-one beta-two],
        "model_ids" => [@alpha.id, @beta.id],
        "tag" => "fixture"
      },
      by_kind["organize"].payload
    )
    assert_equal "Tag a fixture shelf across alpha-one, beta-two", by_kind["organize"].summary
  end

  test "single model omits move and merge" do
    drafts = CurationStubProposals.new(@library, models: [@alpha]).drafts
    assert_equal %w[tag rename organize], drafts.map(&:kind)
    assert_equal(
      ["stub:tag:alpha-one", "stub:rename:alpha-one", "stub:organize:fixture"],
      drafts.map(&:sidecar_ref)
    )
  end

  test "skips rename when every folder is already curated" do
    curated = @library.vibe_models.create!(folder_name: "gamma-curated", title: "Gamma Curated")
    drafts = CurationStubProposals.new(@library, models: [curated]).drafts
    refute drafts.any? { |draft| draft.kind == "rename" }
    assert drafts.any? { |draft| draft.kind == "tag" && draft.sidecar_ref == "stub:tag:gamma-curated" }
  end

  test "skips move when the second folder is already a shelf" do
    shelf = @library.vibe_models.create!(folder_name: "beta-two-shelf", title: "Beta Two Shelf")
    drafts = CurationStubProposals.new(@library, models: [@alpha, shelf]).drafts
    refute drafts.any? { |draft| draft.kind == "move" }
    assert drafts.any? { |draft| draft.kind == "merge" && draft.sidecar_ref == "stub:merge:alpha-one:beta-two-shelf" }
  end

  test "blank folder token falls back to fixture tag" do
    odd = @library.vibe_models.create!(folder_name: "-odd", title: "Odd")
    tag = CurationStubProposals.new(@library, models: [odd]).drafts.find { |draft| draft.kind == "tag" }
    assert_equal "fixture", tag.payload["tag"]
    assert_equal "stub:tag:-odd", tag.sidecar_ref
  end

  test "omits invented confidence and rationale" do
    CurationStubProposals.new(@library).drafts.each do |draft|
      refute draft.payload.key?("confidence")
      refute draft.payload.key?("rationale")
      refute draft.payload.key?("reason")
      refute draft.payload.key?("explanation")
    end
  end

  test "CurationSidecar stub mode still uses the in-process list" do
    sidecar = CurationSidecar.new(@library, endpoint: "stub")
    records = sidecar.ingest_remote!
    assert_equal(
      [
        "stub:tag:alpha-one",
        "stub:rename:alpha-one",
        "stub:move:beta-two",
        "stub:merge:alpha-one:beta-two",
        "stub:organize:fixture"
      ],
      records.map(&:sidecar_ref)
    )
    assert_equal "stub", @library.reload.last_provider
    assert_nil @library.last_error
  end
end
