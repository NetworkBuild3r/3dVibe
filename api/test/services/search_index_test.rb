require "test_helper"

class SearchIndexTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def setup
    @library = Library.create!(name: "Index", root_path: "/tmp/unused-index")
    @alpha = @library.vibe_models.create!(folder_name: "alpha", title: "Alpha")
    @bravo = @library.vibe_models.create!(folder_name: "bravo", title: "Bravo")
  end

  test "debounce and batch stay clamped" do
    previous_d = ENV["VIBE_SEARCH_INDEX_DEBOUNCE"]
    previous_b = ENV["VIBE_SEARCH_INDEX_BATCH"]
    ENV["VIBE_SEARCH_INDEX_DEBOUNCE"] = "-1"
    assert_equal 0, SearchIndex.debounce_seconds
    ENV["VIBE_SEARCH_INDEX_DEBOUNCE"] = "99"
    assert_equal 30, SearchIndex.debounce_seconds
    ENV["VIBE_SEARCH_INDEX_BATCH"] = "0"
    assert_equal 1, SearchIndex.batch_size
    ENV["VIBE_SEARCH_INDEX_BATCH"] = "9999"
    assert_equal 500, SearchIndex.batch_size
  ensure
    if previous_d.nil?
      ENV.delete("VIBE_SEARCH_INDEX_DEBOUNCE")
    else
      ENV["VIBE_SEARCH_INDEX_DEBOUNCE"] = previous_d
    end
    if previous_b.nil?
      ENV.delete("VIBE_SEARCH_INDEX_BATCH")
    else
      ENV["VIBE_SEARCH_INDEX_BATCH"] = previous_b
    end
  end

  test "enqueue coalesces unique model ids into one bulk job" do
    ENV["MEILI_URL"] = "http://127.0.0.1:9"
    assert_enqueued_jobs 1, only: BulkIndexVibeModelsJob do
      SearchIndex.enqueue(@alpha)
      SearchIndex.enqueue(@alpha)
      SearchIndex.enqueue_ids([@alpha.id, @bravo.id, @bravo])
    end
    assert_equal [@alpha.id, @bravo.id].sort, SearchIndexBuffer.pending_ids.sort
    assert_no_enqueued_jobs only: IndexVibeModelJob
  ensure
    ENV.delete("MEILI_URL")
  end

  test "cover write-back ready and failed share the same bulk flush" do
    ENV["MEILI_URL"] = "http://127.0.0.1:9"
    assert_enqueued_jobs 1, only: BulkIndexVibeModelsJob do
      CoverWriteback.apply!("model_id" => @alpha.id, "status" => "ready", "cover_url" => "/covers/a.webp")
      CoverWriteback.apply!("model_id" => @bravo.id, "status" => "failed")
    end
    assert_equal [@alpha.id, @bravo.id].sort, SearchIndexBuffer.pending_ids.sort
    assert @alpha.reload.has_cover?
    assert_equal VibeModel::COVER_FAILED, @bravo.reload.cover_status
    assert_equal true, SearchIndex.new.document_for(@alpha)[:has_cover]
    assert_equal false, SearchIndex.new.document_for(@bravo)[:has_cover]
    assert_equal VibeModel::COVER_FAILED, SearchIndex.new.document_for(@bravo)[:cover_status]
  ensure
    ENV.delete("MEILI_URL")
  end

  test "bulk job upserts a batch then accepts a new flush" do
    ENV["MEILI_URL"] = "http://127.0.0.1:9"
    client = RecordingMeili.new
    SearchIndex.enqueue_ids([@alpha.id, @bravo.id])
    assert_equal :ok, SearchIndex.new(client: client).upsert_many(SearchIndexBuffer.drain)
    assert_equal 2, client.documents.size
    assert_equal [@alpha.id, @bravo.id].sort, client.documents.map { |doc| doc[:id] }.sort
    assert_includes client.documents.map { |doc| doc[:cover_status] }, @alpha.cover_status

    SearchIndexBuffer.release_flush!
    assert_enqueued_with(job: BulkIndexVibeModelsJob) do
      SearchIndex.enqueue(@alpha)
    end
    assert_includes SearchIndexBuffer.pending_ids, @alpha.id
  ensure
    ENV.delete("MEILI_URL")
  end

  test "bulk index job drains the buffer without raising when Meili is down" do
    ENV["MEILI_URL"] = "http://127.0.0.1:9"
    SearchIndex.enqueue(@alpha)
    assert_includes SearchIndexBuffer.pending_ids, @alpha.id
    assert_nothing_raised { BulkIndexVibeModelsJob.perform_now }
    assert_empty SearchIndexBuffer.pending_ids
  ensure
    ENV.delete("MEILI_URL")
  end

  class RecordingMeili
    attr_reader :documents

    def initialize
      @documents = []
    end

    def configured?
      true
    end

    def available?
      true
    end

    def ensure_index!
      true
    end

    def upsert_documents(docs)
      @documents.concat(Array(docs))
    end
  end
end
