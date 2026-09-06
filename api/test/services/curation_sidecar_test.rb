require "test_helper"
require "json"
require "socket"

class CurationSidecarTest < ActiveSupport::TestCase
  def setup
    @root = Rails.root.join("tmp/sidecar-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(@root.join("Mz4250 - Alpha One"))
    File.write(@root.join("Mz4250 - Alpha One/a.stl"), "solid a\nendsolid a\n")
    File.write(@root.join("Mz4250 - Alpha One/pack.zip"), "PK\x03\x04")
    FileUtils.mkdir_p(@root.join("beta-two"))
    File.write(@root.join("beta-two/b.stl"), "solid b\nendsolid b\n")
    @library = Library.create!(name: "Sidecar", root_path: @root.to_s)
    LibraryScanner.new(@library).scan!
    @alpha = @library.vibe_models.find_by!(folder_name: "Mz4250 - Alpha One")
    @alpha.update!(cover_status: VibeModel::COVER_READY)
  end

  def teardown
    FileUtils.rm_rf(@root)
    @http&.stop
  end

  test "stub mode emits deterministic drafts and upserts by sidecar_ref" do
    sidecar = CurationSidecar.new(@library, endpoint: "stub")
    first = sidecar.ingest_remote!
    second = sidecar.ingest_remote!

    assert first.size >= 3
    assert_equal first.map(&:id).sort, second.map(&:id).sort
    assert_equal first.size, @library.curation_proposals.where(status: "pending").count
    assert first.any? { |proposal| proposal.kind == "tag" }
    assert first.any? { |proposal| proposal.kind == "rename" }
    assert first.any? { |proposal| proposal.kind == "merge" }
    refs = first.map(&:sidecar_ref)
    assert refs.all?(&:present?)
    assert_equal refs.uniq.size, refs.size
  end

  test "does not clobber an already reviewed sidecar_ref" do
    sidecar = CurationSidecar.new(@library, endpoint: "stub")
    records = sidecar.ingest_remote!
    kept = records.find { |proposal| proposal.kind == "tag" }
    kept.update!(status: CurationProposal::REJECTED, reviewed_at: Time.current)

    sidecar.ingest_remote!
    assert_equal CurationProposal::REJECTED, kept.reload.status
    assert_equal 1, @library.curation_proposals.where(sidecar_ref: kept.sidecar_ref).count
  end

  test "blank endpoint without stub mode returns no drafts" do
    sidecar = CurationSidecar.new(@library, endpoint: "")
    sidecar.define_singleton_method(:stub_mode?) { false }
    assert_equal [], sidecar.fetch_drafts
  end

  test "catalog includes locked snapshot fields without file bytes" do
    ENV["VIBE_CURATOR_PROVIDER"] = "ollama"
    catalog = CurationSidecar.new(@library, endpoint: "stub").catalog

    assert_equal @library.id, catalog[:library_id]
    assert_equal @library.name, catalog[:library_name]
    assert_equal @library.root_path, catalog[:library_root]
    assert_equal "ollama", catalog[:provider_hint]
    assert catalog[:models].all? { |row| row.key?(:id) && row.key?(:folder_name) && row.key?(:title) }
    assert catalog[:models].all? { |row| row.key?(:tags) && row.key?(:asset_count) && row.key?(:byte_size) }

    alpha = catalog[:models].find { |row| row[:folder_name] == "Mz4250 - Alpha One" }
    assert_equal({ id: @alpha.creator.id, slug: "mz4250", name: "Mz4250" }, alpha[:creator])
    assert_equal VibeModel::COVER_READY, alpha[:cover_status]
    assert_equal 1, alpha[:mesh_count]
    assert_equal 1, alpha[:archive_count]
    assert alpha[:has_archives]
    assert_equal ["Mz4250 - Alpha One/a.stl", "Mz4250 - Alpha One/pack.zip"], alpha[:sample_paths]
    refute alpha.key?(:bytes)
    refute alpha[:sample_paths].any? { |path| path.include?("\0") || path.bytesize > 400 }

    index = catalog[:creators_index]
    assert index.is_a?(Array)
    mz = index.find { |row| row[:slug] == "mz4250" }
    assert_equal 1, mz[:model_count]
    assert_equal "Mz4250", mz[:name]
  ensure
    ENV.delete("VIBE_CURATOR_PROVIDER")
  end

  test "poll success clears last_error and sets last_polled_at" do
    @library.update!(last_error: "stale sidecar", last_provider: "xai", last_polled_at: 2.days.ago)
    sidecar = CurationSidecar.new(@library, endpoint: "stub", provider_hint: "stub")

    records = sidecar.ingest_remote!
    assert records.size >= 3

    @library.reload
    assert_nil @library.last_error
    assert_equal "stub", @library.last_provider
    assert @library.last_polled_at > 1.minute.ago
  end

  test "poll failure records last_error without leaving a stale success" do
    @library.update!(last_error: nil, last_provider: "stub", last_polled_at: nil)
    client = FailingCuratorClient.new("curator unreachable: test")
    sidecar = CurationSidecar.new(@library, endpoint: "http://curator.test", client: client)

    error = assert_raises(CurationHttpClient::Error) { sidecar.ingest_remote! }
    assert_equal "curator unreachable: test", error.message

    @library.reload
    assert_equal "curator unreachable: test", @library.last_error
    assert @library.last_polled_at.present?
    assert_equal "stub", @library.last_provider
    assert @library.curation_proposals.none?
  end

  test "HTTP client posts the catalog and parses proposals" do
    body = {
      proposals: [
        {
          kind: "tag",
          summary: "From HTTP",
          sidecar_ref: "http:tag:alpha-one",
          payload: { tag: "remote", folder_name: "alpha-one" }
        }
      ]
    }
    @http = MiniCuratorServer.new(JSON.generate(body))
    port = @http.start

    sidecar = CurationSidecar.new(@library, endpoint: "http://127.0.0.1:#{port}", token: "secret", provider_hint: "xai")
    records = sidecar.ingest_remote!
    assert_equal 1, records.size
    assert_equal "From HTTP", records.first.summary
    assert_equal "remote", records.first.payload["tag"]
    assert @http.last_auth.to_s.include?("secret")
    assert_equal @library.id, @http.last_catalog["library_id"]
    assert_equal "xai", @http.last_catalog["provider_hint"]
    assert @http.last_catalog["models"].first.key?("cover_status")
    assert @http.last_catalog.key?("creators_index")
    assert_equal "live-xai", @library.reload.last_provider
    assert_nil @library.last_error
  end

  test "payload_with_hints copies optional keys without inventing" do
    payload = CurationSidecar.payload_with_hints(
      "kind" => "tag",
      "rationale" => "Because",
      "payload" => { "tag" => "x", "confidence" => 0.4 }
    )
    assert_equal "Because", payload["rationale"]
    assert_in_delta 0.4, payload["confidence"]
    refute payload.key?("explanation")

    kept = CurationSidecar.payload_with_hints(
      "rationale" => "top",
      "payload" => { "rationale" => "inner" }
    )
    assert_equal "inner", kept["rationale"]

    empty = CurationSidecar.payload_with_hints("kind" => "tag", "payload" => { "tag" => "x" })
    refute empty.key?("rationale")
    refute empty.key?("confidence")
  end

  test "HTTP drafts fold optional rationale and confidence into payload" do
    body = {
      proposals: [
        {
          kind: "tag",
          summary: "From HTTP",
          sidecar_ref: "http:tag:hints",
          rationale: "Cover and mesh counts agree",
          confidence: 0.7,
          payload: { tag: "remote", folder_name: "Mz4250 - Alpha One" }
        }
      ]
    }
    @http = MiniCuratorServer.new(JSON.generate(body))
    port = @http.start

    sidecar = CurationSidecar.new(@library, endpoint: "http://127.0.0.1:#{port}", token: "secret")
    records = sidecar.ingest_remote!
    assert_equal 1, records.size
    assert_equal "Cover and mesh counts agree", records.first.payload["rationale"]
    assert_in_delta 0.7, records.first.payload["confidence"].to_f
    refute records.first.payload.key?("explanation")
  end

  class FailingCuratorClient
    def initialize(message)
      @message = message
    end

    def fetch_proposals(_catalog)
      raise CurationHttpClient::Error, @message
    end
  end

  class MiniCuratorServer
    attr_reader :last_auth, :last_catalog

    def initialize(body)
      @body = body
    end

    def start
      @server = TCPServer.new("127.0.0.1", 0)
      @thread = Thread.new { handle }
      @server.addr[1]
    end

    def stop
      @thread&.kill
      @server&.close
    rescue IOError
      nil
    end

    private

    def handle
      socket = @server.accept
      headers = []
      loop do
        line = socket.gets
        break if line.nil? || line == "\r\n"

        headers << line
      end
      length = headers.join[/Content-Length: (\d+)/i, 1].to_i
      raw = length.positive? ? socket.read(length) : "{}"
      @last_auth = headers.join
      @last_catalog = JSON.parse(raw)
      socket.write("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nX-Curator-Provider: live-xai\r\nContent-Length: #{@body.bytesize}\r\nConnection: close\r\n\r\n#{@body}")
      socket.close
    rescue IOError
      nil
    end
  end
end
