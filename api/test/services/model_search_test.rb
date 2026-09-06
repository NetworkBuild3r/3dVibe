require "test_helper"
require "fileutils"
require "zip"

class ModelSearchTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def setup
    @root = Rails.root.join("tmp/search-lib-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(@root.join("signal-horn"))
    File.write(@root.join("signal-horn/horn.stl"), "solid x\nendsolid x\n")
    File.write(@root.join("signal-horn/readme.txt"), "Handheld signal horn.")
    FileUtils.mkdir_p(@root.join("quiet-box"))
    File.write(@root.join("quiet-box/notes.txt"), "No mesh here.")
    FileUtils.mkdir_p(@root.join("packed-minis"))
    Zip::File.open(@root.join("packed-minis/minis.zip"), Zip::File::CREATE) do |zip|
      zip.get_output_stream("hero.stl") { |io| io.write("solid x\nendsolid x\n") }
    end
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
    result = ModelSearch.new(library_scope, query: "horn").call
    assert_equal "postgres", result.engine
    refute result.fallback
    assert_includes result.models.map(&:id), @horn.id
    refute_includes result.models.map(&:id), @box.id
    assert result.facets["tags"].key?("stl")
  end

  test "postgres filters by tag and has_preview with offset" do
    preview = ModelSearch.new(library_scope, query: "", filters: { has_preview: true }).call
    assert_includes preview.models.map(&:id), @horn.id
    refute_includes preview.models.map(&:id), @box.id

    tagged = ModelSearch.new(library_scope, query: "", filters: { tags: ["stl"] }).call
    assert_equal [@horn.id], tagged.models.map(&:id)

    page = ModelSearch.new(library_scope, query: "", offset: 0, limit: 1).call
    assert_equal 1, page.models.size
    assert_equal 1, page.next_offset
    assert_equal 3, page.estimated_total
  end

  test "postgres finds a model by a member path inside a zip" do
    pack = @library.vibe_models.find_by!(folder_name: "packed-minis")
    result = ModelSearch.new(library_scope, query: "hero").call
    assert_includes result.models.map(&:id), pack.id
    refute_includes result.models.map(&:id), @box.id

    doc = SearchIndex.new.document_for(pack)
    assert_includes doc[:archive_paths], "hero.stl"
    refute_includes doc[:archive_paths], ArchiveMember::PLACEHOLDER_PATH
  end

  test "meilisearch stub hydrates hits in ranked order" do
    client = FakeMeili.new(hits: [{ "id" => @box.id }, { "id" => @horn.id }], total: 2)
    result = ModelSearch.new(library_scope, query: "anything", client: client).call
    assert_equal "meilisearch", result.engine
    refute result.fallback
    assert_equal [@box.id, @horn.id], result.models.map(&:id)
    assert_equal 2, result.estimated_total
    assert_equal 1, result.facets.dig("tags", "stl")
  end

  test "meilisearch outage falls back to postgres" do
    client = FakeMeili.new(error: MeilisearchClient::Error.new("connection refused"))
    result = ModelSearch.new(library_scope, query: "horn", client: client).call
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
    assert_equal @horn.creator&.slug, doc[:creator_slug]
    assert_equal @horn.creator&.slug, doc[:creator]
    assert_equal @horn.cover_status, doc[:cover_status]
    assert_equal @horn.has_cover?, doc[:has_cover]
  end

  test "postgres filters by creator_slug and ILIKE-matches creator name" do
    slug = @horn.creator.slug
    filtered = ModelSearch.new(library_scope, query: "", filters: { creator_slug: slug }).call
    assert_includes filtered.models.map(&:id), @horn.id
    refute_includes filtered.models.map(&:id), @box.id
    assert filtered.facets["creator_slug"].key?(slug)

    named = ModelSearch.new(library_scope, query: @horn.creator.name).call
    assert_includes named.models.map(&:id), @horn.id
  end

  test "postgres filters by has_cover and cover_status and exposes cover facets" do
    @horn.update!(cover_status: VibeModel::COVER_READY, cover_url: "/covers/horn.webp", cover_placeholder: false)
    @box.update!(cover_status: VibeModel::COVER_MISSING)

    covered = ModelSearch.new(library_scope, query: "", filters: { has_cover: true }).call
    assert_includes covered.models.map(&:id), @horn.id
    refute_includes covered.models.map(&:id), @box.id
    assert covered.facets["has_cover"]["true"] >= 1
    assert covered.facets["cover_status"][VibeModel::COVER_READY] >= 1
    refute covered.capped

    pending = ModelSearch.new(library_scope, query: "", filters: { cover_status: VibeModel::COVER_PENDING }).call
    refute_includes pending.models.map(&:id), @horn.id
    assert pending.facets["cover_status"].key?(VibeModel::COVER_PENDING) || pending.models.empty?
  end

  test "meilisearch requests creator tag and cover facets" do
    client = FakeMeili.new(hits: [{ "id" => @horn.id }], total: 1)
    @horn.update!(cover_status: VibeModel::COVER_READY)
    result = ModelSearch.new(
      library_scope,
      query: "horn",
      filters: { creator_slug: @horn.creator.slug, tags: ["stl"], has_cover: true, cover_status: "ready" },
      client: client
    ).call
    assert_equal "meilisearch", result.engine
    assert_includes client.last_facets, "creator_slug"
    assert_includes client.last_facets, "cover_status"
    assert_includes client.last_facets, "has_cover"
    assert_includes client.last_filter, "creator_slug ="
    assert_includes client.last_filter, "tags = \"stl\""
    assert_includes client.last_filter, "has_cover = true"
    assert_includes client.last_filter, "cover_status = \"ready\""
    assert result.facets.key?("cover_status")
    assert result.facets.key?("has_cover")
  end

  test "postgres fallback caps ILIKE candidate ids so joins cannot melt" do
    previous = ENV["VIBE_SEARCH_FALLBACK_CAP"]
    ENV["VIBE_SEARCH_FALLBACK_CAP"] = "1"
    result = ModelSearch.new(library_scope, query: "e").call
    assert result.capped
    assert_equal 1, result.estimated_total
    assert_operator result.models.size, :<=, 1
  ensure
    if previous.nil?
      ENV.delete("VIBE_SEARCH_FALLBACK_CAP")
    else
      ENV["VIBE_SEARCH_FALLBACK_CAP"] = previous
    end
  end

  test "cover writeback and creator assign enqueue search reindex when Meili is configured" do
    ENV["MEILI_URL"] = "http://127.0.0.1:9"
    assert_enqueued_with(job: IndexVibeModelJob, args: [@horn.id]) do
      CoverWriteback.apply!("model_id" => @horn.id, "status" => "ready", "cover_url" => "/covers/horn.webp")
    end
    assert @horn.reload.has_cover?
    doc = SearchIndex.new.document_for(@horn)
    assert_equal true, doc[:has_cover]
    assert_equal VibeModel::COVER_READY, doc[:cover_status]

    creator = Creator.create!(slug: "fresh-label", name: "Fresh Label", source: Creator::SOURCE_NFS)
    assert_enqueued_with(job: IndexVibeModelJob, args: [@horn.id]) do
      @horn.update!(creator: creator)
    end
    assert_equal "fresh-label", SearchIndex.new.document_for(@horn.reload)[:creator_slug]
  ensure
    ENV.delete("MEILI_URL")
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

  def library_scope
    @library.vibe_models
  end

  class FakeMeili
    attr_reader :last_filter, :last_facets

    def initialize(hits: [], total: nil, error: nil)
      @hits = hits
      @total = total || hits.size
      @error = error
    end

    def configured?
      true
    end

    def search(*args, **kwargs)
      raise @error if @error

      options = kwargs
      options = args.last if options.empty? && args.last.is_a?(Hash)
      @last_filter = options[:filter] || options["filter"]
      @last_facets = options[:facets] || options["facets"]

      {
        "hits" => @hits,
        "estimatedTotalHits" => @total,
        "facetDistribution" => {
          "tags" => { "stl" => 1 },
          "has_preview" => { "true" => 1 },
          "creator_slug" => { "signal-horn" => 1 },
          "cover_status" => { "ready" => 1 },
          "has_cover" => { "true" => 1 }
        }
      }
    end
  end
end
