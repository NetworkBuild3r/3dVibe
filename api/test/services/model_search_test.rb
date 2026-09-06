require "test_helper"
require "fileutils"

class ModelSearchTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def setup
    @root = Rails.root.join("tmp/search-lib-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(@root.join("signal-horn"))
    File.write(@root.join("signal-horn/horn.stl"), "solid x\nendsolid x\n")
    File.write(@root.join("signal-horn/readme.txt"), "Handheld signal horn.")
    FileUtils.mkdir_p(@root.join("quiet-box"))
    File.write(@root.join("quiet-box/notes.txt"), "No mesh here.")
    @owner = create_owner!
    @library = Library.create!(name: "Search", root_path: @root.to_s)
    Membership.create!(user: @owner, library: @library, role: Membership::OWNER)
    LibraryScanner.new(@library, uploaded_by: @owner).scan!
    @horn = @library.vibe_models.find_by!(folder_name: "signal-horn")
    @box = @library.vibe_models.find_by!(folder_name: "quiet-box")
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  test "postgres fallback finds title, path, tags, and file names" do
    result = ModelSearch.new(VibeModel.all, query: "horn").call
    assert_equal "postgres", result.engine
    refute result.fallback
    assert_includes result.models.map(&:id), @horn.id
    refute_includes result.models.map(&:id), @box.id
    assert result.facets["tags"].key?("stl")
  end

  test "postgres filters by tag and has_preview with offset" do
    preview = ModelSearch.new(VibeModel.all, query: "", filters: { has_preview: true }).call
    assert_includes preview.models.map(&:id), @horn.id
    refute_includes preview.models.map(&:id), @box.id

    tagged = ModelSearch.new(VibeModel.all, query: "", filters: { tags: ["stl"] }).call
    assert_equal [@horn.id], tagged.models.map(&:id)

    page = ModelSearch.new(VibeModel.all, query: "", offset: 0, limit: 1).call
    assert_equal 1, page.models.size
    assert_equal 1, page.next_offset
    assert_equal 2, page.estimated_total
  end

  test "meilisearch stub hydrates hits in ranked order" do
    client = FakeMeili.new(hits: [{ "id" => @box.id }, { "id" => @horn.id }], total: 2)
    result = ModelSearch.new(VibeModel.all, query: "anything", client: client).call
    assert_equal "meilisearch", result.engine
    refute result.fallback
    assert_equal [@box.id, @horn.id], result.models.map(&:id)
    assert_equal 2, result.estimated_total
    assert_equal 1, result.facets.dig("tags", "stl")
  end

  test "meilisearch outage falls back to postgres" do
    client = FakeMeili.new(error: MeilisearchClient::Error.new("connection refused"))
    result = ModelSearch.new(VibeModel.all, query: "horn", client: client).call
    assert_equal "postgres", result.engine
    assert result.fallback
    assert_includes result.models.map(&:id), @horn.id
  end

  test "search index document includes file and archive fields" do
    doc = SearchIndex.new.document_for(@horn)
    assert_equal @horn.id, doc[:id]
    assert_equal "Signal Horn", doc[:name]
    assert_includes doc[:filenames], "horn.stl"
    assert_includes doc[:tags], "stl"
    assert_equal @owner.display_name, doc[:uploader]
    assert doc[:has_preview]
    assert_includes doc[:kinds], "stl"
  end

  test "search index enqueue is a no-op without MEILI_URL" do
    assert_no_enqueued_jobs only: IndexVibeModelJob do
      SearchIndex.enqueue(@horn)
    end
  end

  test "search index enqueue and remove jobs when Meili is configured" do
    ENV["MEILI_URL"] = "http://127.0.0.1:9"
    assert_enqueued_with(job: IndexVibeModelJob, args: [@horn.id]) do
      SearchIndex.enqueue(@horn)
    end
    assert_enqueued_with(job: RemoveVibeModelIndexJob, args: [@horn.id]) do
      SearchIndex.enqueue_remove(@horn.id)
    end
  ensure
    ENV.delete("MEILI_URL")
  end

  class FakeMeili
    def initialize(hits: [], total: nil, error: nil)
      @hits = hits
      @total = total || hits.size
      @error = error
    end

    def configured?
      true
    end

    def search(*)
      raise @error if @error

      {
        "hits" => @hits,
        "estimatedTotalHits" => @total,
        "facetDistribution" => { "tags" => { "stl" => 1 }, "has_preview" => { "true" => 1 } }
      }
    end
  end
end
