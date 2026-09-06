require "test_helper"
require "fileutils"
require "minitest/mock"

class PrinterBridgeServiceTest < ActiveSupport::TestCase
  def setup
    @root = Rails.root.join("tmp/bridge-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(@root.join("signal-horn"))
    File.write(@root.join("signal-horn/horn.stl"), "solid x\nendsolid x\n")
    @owner = create_owner!
    @library = Library.create!(name: "Bridge", root_path: @root.to_s)
    Membership.create!(user: @owner, library: @library, role: Membership::OWNER)
    LibraryScanner.new(@library).scan!
    @model = @library.vibe_models.find_by!(folder_name: "signal-horn")
    @asset = @model.assets.find_by!(filename: "horn.stl")
    @printer = @library.printers.create!(name: "Mock", host: "127.0.0.1", protocol_type: Printer::MOCK)
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  test "mock adapter walks to succeeded and reads the jailed file" do
    job = build_job
    PrinterBridge.new(job).run!
    job.reload
    assert_equal PrintDispatch::SUCCEEDED, job.status
    assert_equal 100, job.progress
    assert_equal "mock-#{job.id}-horn.stl", job.remote_ref
    assert job.started_at.present?
    assert job.finished_at.present?
  end

  test "missing file fails soft" do
    job = build_job
    FileUtils.rm_f(@root.join("signal-horn/horn.stl"))
    PrinterBridge.new(job).run!
    job.reload
    assert_equal PrintDispatch::FAILED, job.status
    assert_match(/print file is not in the library|No such file/i, job.error_message)
  end

  test "timeout fails soft instead of raising" do
    job = build_job
    previous = ENV["VIBE_PRINT_TIMEOUT"]
    ENV["VIBE_PRINT_TIMEOUT"] = "1"
    adapter = PrinterAdapters::Mock.new(@printer, timeout: 1)
    adapter.define_singleton_method(:submit) do |*_args, **_kwargs|
      sleep 2
      { remote_ref: "late" }
    end
    PrinterAdapters.stub(:for, adapter) do
      PrinterBridge.new(job).run!
    end
    job.reload
    assert_equal PrintDispatch::FAILED, job.status
    assert_match(/timed out|exceeded/i, job.error_message)
  ensure
    ENV["VIBE_PRINT_TIMEOUT"] = previous
  end

  test "resolver stays inside the library jail" do
    jail = LibraryPathJail.new(@root)
    path = jail.resolve_file("signal-horn", "horn.stl")
    assert_equal @root.join("signal-horn/horn.stl").realpath.to_s, path.to_s
    assert_raises(ArgumentError) { jail.resolve_file("signal-horn", "../horn.stl") }
    assert_raises(ArgumentError) { jail.resolve_file("..", "horn.stl") }
  end

  test "sdcp adapter is an explicit not-configured interface" do
    sdcp = @library.printers.create!(name: "SDCP", host: "10.0.0.5", protocol_type: Printer::SDCP)
    job = build_job(printer: sdcp)
    PrinterBridge.new(job).run!
    job.reload
    assert_equal PrintDispatch::FAILED, job.status
    assert_match(/not implemented/i, job.error_message)
  end

  test "dispatch job never raises to the web process" do
    job = build_job
    assert_nothing_raised { DispatchPrintJob.perform_now(job.id) }
    assert_equal PrintDispatch::SUCCEEDED, job.reload.status
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
