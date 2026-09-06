require "test_helper"
require "fileutils"

class PrinterAdaptersSdcpTest < ActiveSupport::TestCase
  def setup
    @root = Rails.root.join("tmp/sdcp-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(@root.join("signal-horn"))
    File.write(@root.join("signal-horn/horn.stl"), "solid x\nendsolid x\n")
    @owner = create_owner!
    @library = Library.create!(name: "SDCP", root_path: @root.to_s)
    Membership.create!(user: @owner, library: @library, role: Membership::OWNER)
    LibraryScanner.new(@library).scan!
    @model = @library.vibe_models.find_by!(folder_name: "signal-horn")
    @asset = @model.assets.find_by!(filename: "horn.stl")
    @printer = @library.printers.create!(
      name: "LAN resin",
      host: "10.0.0.40",
      protocol_type: Printer::SDCP,
      settings: { "mainboard_id" => "000000000001d354", "client_id" => "3dvibe-test" }
    )
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  test "envelope matches SDCP v3 request shape" do
    payload = PrinterAdapters::Sdcp.envelope(
      cmd: PrinterAdapters::Sdcp::CMD_START_PRINT,
      data: { "Filename" => "horn.stl", "StartLayer" => 0 },
      request_id: "req1",
      mainboard_id: "000000000001d354",
      client_id: "3dvibe-test",
      time: 1_687_069_655
    )
    assert_equal "3dvibe-test", payload["Id"]
    assert_equal "sdcp/request/000000000001d354", payload["Topic"]
    assert_equal 128, payload.dig("Data", "Cmd")
    assert_equal "horn.stl", payload.dig("Data", "Data", "Filename")
    assert_equal 0, payload.dig("Data", "Data", "StartLayer")
    assert_equal "req1", payload.dig("Data", "RequestID")
    assert_equal "000000000001d354", payload.dig("Data", "MainboardID")
    assert_equal 1_687_069_655, payload.dig("Data", "TimeStamp")
    assert_equal 0, payload.dig("Data", "From")
  end

  test "upload form fields match the documented HTTP chunk" do
    fields = PrinterAdapters::Sdcp.upload_form_fields(
      filename: "horn.stl",
      md5: "d" * 32,
      uuid: "u" * 32,
      size: 12,
      offset: 0
    )
    assert_equal "d" * 32, fields["S-File-MD5"]
    assert_equal "1", fields["Check"]
    assert_equal "0", fields["Offset"]
    assert_equal "u" * 32, fields["Uuid"]
    assert_equal "12", fields["TotalSize"]
  end

  test "stubbed transport walks queued to succeeded and records SDCP shapes" do
    transport = PrinterAdapters::Sdcp::StubTransport.new(@printer, timeout: 5)
    job = build_job
    PrinterBridge.new(job, adapter: PrinterAdapters::Sdcp.new(@printer, timeout: 5, transport: transport)).run!
    job.reload
    assert_equal PrintDispatch::SUCCEEDED, job.status
    assert_equal 100, job.progress
    assert job.remote_ref.to_s.start_with?("sdcp-")
    assert_nil job.error_message
    assert_equal [0, 128], transport.commands.map { |row| row[:cmd] }
    assert_equal "horn.stl", transport.uploads.first[:filename]
    assert_equal 128, transport.commands.last[:envelope].dig("Data", "Cmd")
    assert transport.closed?
  end

  test "stubbed transport busy Ack fails soft" do
    transport = PrinterAdapters::Sdcp::StubTransport.new(@printer, timeout: 5, script: { command: { 128 => :busy } })
    job = build_job
    PrinterBridge.new(job, adapter: PrinterAdapters::Sdcp.new(@printer, timeout: 5, transport: transport)).run!
    job.reload
    assert_equal PrintDispatch::FAILED, job.status
    assert_match(/busy/i, job.error_message)
  end

  test "stubbed transport timeout fails soft" do
    transport = PrinterAdapters::Sdcp::StubTransport.new(@printer, timeout: 1, script: { connect: :timeout })
    job = build_job
    PrinterBridge.new(job, adapter: PrinterAdapters::Sdcp.new(@printer, timeout: 1, transport: transport)).run!
    job.reload
    assert_equal PrintDispatch::FAILED, job.status
    assert_match(/timed out/i, job.error_message)
  end

  test "live transport against a closed port fails soft without raising" do
    live = @library.printers.create!(
      name: "Closed port",
      host: "127.0.0.1",
      protocol_type: Printer::SDCP,
      settings: { "port" => 1 }
    )
    job = build_job(printer: live)
    assert_nothing_raised { PrinterBridge.new(job).run! }
    job.reload
    assert_equal PrintDispatch::FAILED, job.status
    assert_match(/unreachable|timed out|refused|SDCP/i, job.error_message)
    refute_equal PrintDispatch::SUCCEEDED, job.status
  end

  test "test-env stub setting completes through the default adapter" do
    @printer.update!(settings: @printer.settings.merge("stub" => true))
    job = build_job
    PrinterBridge.new(job).run!
    job.reload
    assert_equal PrintDispatch::SUCCEEDED, job.status
  end

  private

  def build_job(printer: @printer)
    PrintDispatch.create!(
      library: @library,
      printer: printer,
      vibe_model: @model,
      asset: @asset,
      requested_by: @owner,
      status: PrintDispatch::QUEUED,
      protocol_type: printer.protocol_type,
      filename: @asset.filename,
      printer_hint: printer.name
    )
  end
end
