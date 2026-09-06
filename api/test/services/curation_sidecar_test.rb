require "test_helper"
require "json"
require "socket"

class CurationSidecarTest < ActiveSupport::TestCase
  def setup
    @root = Rails.root.join("tmp/sidecar-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(@root.join("alpha-one"))
    File.write(@root.join("alpha-one/a.stl"), "solid a\nendsolid a\n")
    FileUtils.mkdir_p(@root.join("beta-two"))
    File.write(@root.join("beta-two/b.stl"), "solid b\nendsolid b\n")
    @library = Library.create!(name: "Sidecar", root_path: @root.to_s)
    LibraryScanner.new(@library).scan!
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

    sidecar = CurationSidecar.new(@library, endpoint: "http://127.0.0.1:#{port}", token: "secret")
    records = sidecar.ingest_remote!
    assert_equal 1, records.size
    assert_equal "From HTTP", records.first.summary
    assert_equal "remote", records.first.payload["tag"]
    assert @http.last_auth.to_s.include?("secret")
    assert_equal @library.id, @http.last_catalog["library_id"]
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
      socket.write("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: #{@body.bytesize}\r\nConnection: close\r\n\r\n#{@body}")
      socket.close
    rescue IOError
      nil
    end
  end
end
