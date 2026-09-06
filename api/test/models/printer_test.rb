require "test_helper"

class PrinterTest < ActiveSupport::TestCase
  def setup
    @library = Library.create!(name: "Printers", root_path: "/tmp/printer-model-#{SecureRandom.hex(4)}")
  end

  test "accepts mock and sdcp with a hostname or IP" do
    mock = @library.printers.create!(name: "Studio", host: "127.0.0.1", protocol_type: "MOCK", enabled: true)
    assert_equal Printer::MOCK, mock.protocol_type

    sdcp = @library.printers.create!(name: "Saturn", host: "10.0.0.40:3030", protocol_type: Printer::SDCP)
    assert sdcp.sdcp?
    assert_equal "10.0.0.40", sdcp.endpoint_host
    assert_equal 3030, sdcp.endpoint_port
  end

  test "rejects URL hosts unknown protocols and bad ports" do
    printer = @library.printers.build(name: "Bad", host: "http://10.0.0.40", protocol_type: Printer::MOCK)
    refute printer.valid?
    assert_includes printer.errors[:host], "must be a hostname or IP (no URL)"

    printer.host = "10.0.0.40/upload"
    refute printer.valid?

    printer.host = "10.0.0.40"
    printer.protocol_type = "octoprint"
    refute printer.valid?
    assert_includes printer.errors[:protocol_type], "is not included in the list"

    printer.protocol_type = Printer::SDCP
    printer.settings = { "port" => 0 }
    refute printer.valid?
    assert printer.errors[:settings].any?
  end

  test "settings port wins over host port" do
    printer = @library.printers.create!(
      name: "Ported",
      host: "printer.local:3030",
      protocol_type: Printer::SDCP,
      settings: { "port" => 4040, "token" => "lan-token", "timeout" => 8 }
    )
    assert_equal "printer.local", printer.endpoint_host
    assert_equal 4040, printer.endpoint_port
    assert_equal "lan-token", printer.sdcp_token
    assert_equal 8, printer.sdcp_timeout
    refute printer.sdcp_stub?
  end
end
