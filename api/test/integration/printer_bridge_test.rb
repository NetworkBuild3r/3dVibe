require "test_helper"
require "fileutils"

class PrinterBridgeTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  def setup
    @root = Rails.root.join("tmp/print-lib-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(@root.join("signal-horn"))
    File.write(@root.join("signal-horn/horn.stl"), "solid x\nendsolid x\n")
    File.write(@root.join("signal-horn/readme.txt"), "Handheld signal horn.")

    @password = "secret123"
    @owner = create_owner!(password: @password)
    @contributor = create_user!(email: "contrib@example.test")
    @viewer = create_user!(email: "viewer@example.test")
    @library = Library.create!(name: "Print pile", root_path: @root.to_s)
    Membership.create!(user: @owner, library: @library, role: Membership::OWNER)
    Membership.create!(user: @contributor, library: @library, role: Membership::CONTRIBUTOR)
    Membership.create!(user: @viewer, library: @library, role: Membership::VIEWER)
    LibraryScanner.new(@library).scan!
    @model = @library.vibe_models.find_by!(folder_name: "signal-horn")
    @asset = @model.assets.find_by!(filename: "horn.stl")
    @printer = @library.printers.create!(name: "Studio mock", host: "127.0.0.1", protocol_type: Printer::MOCK, enabled: true)
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  test "owner can add edit and remove printers" do
    post "/api/v1/printers",
         params: { library_id: @library.id, name: "Garage", host: "10.0.0.8", protocol_type: "mock", enabled: true },
         headers: auth_header(@owner),
         as: :json
    assert_response :created
    id = response.parsed_body.dig("printer", "id")

    patch "/api/v1/printers/#{id}",
          params: { notes: "LAN resin", enabled: false },
          headers: auth_header(@owner),
          as: :json
    assert_response :success
    assert_equal "LAN resin", response.parsed_body.dig("printer", "notes")
    refute response.parsed_body.dig("printer", "enabled")

    delete "/api/v1/printers/#{id}", headers: auth_header(@owner), as: :json
    assert_response :no_content
    refute Printer.exists?(id)
  end

  test "viewer and contributor cannot manage printers" do
    post "/api/v1/printers",
         params: { library_id: @library.id, name: "Nope", host: "10.0.0.9", protocol_type: "mock" },
         headers: auth_header(@viewer),
         as: :json
    assert_response :forbidden

    post "/api/v1/printers",
         params: { library_id: @library.id, name: "Nope", host: "10.0.0.9", protocol_type: "mock" },
         headers: auth_header(@contributor),
         as: :json
    assert_response :forbidden

    patch "/api/v1/printers/#{@printer.id}",
          params: { enabled: false },
          headers: auth_header(@contributor),
          as: :json
    assert_response :forbidden

    delete "/api/v1/printers/#{@printer.id}", headers: auth_header(@viewer), as: :json
    assert_response :forbidden
    assert Printer.exists?(@printer.id)
  end

  test "viewer sees only enabled printers" do
    @library.printers.create!(name: "Hidden", host: "10.0.0.2", protocol_type: Printer::MOCK, enabled: false)

    get "/api/v1/printers", headers: auth_header(@viewer)
    assert_response :success
    names = response.parsed_body.fetch("printers").map { |printer| printer["name"] }
    assert_includes names, "Studio mock"
    refute_includes names, "Hidden"

    get "/api/v1/printers", headers: auth_header(@owner)
    assert_response :success
    owner_names = response.parsed_body.fetch("printers").map { |printer| printer["name"] }
    assert_includes owner_names, "Hidden"
  end

  test "only the library owner can queue a mock print that succeeds" do
    job_id = nil
    perform_enqueued_jobs only: DispatchPrintJob do
      post "/api/v1/print_jobs",
           params: { model_id: @model.id, asset_id: @asset.id, printer_id: @printer.id },
           headers: auth_header(@owner),
           as: :json
      assert_response :accepted
      assert_equal PrintDispatch::QUEUED, response.parsed_body.dig("print_job", "status")
      job_id = response.parsed_body.dig("print_job", "id")
    end

    get "/api/v1/print_jobs/#{job_id}", headers: auth_header(@owner)
    assert_response :success
    body = response.parsed_body.fetch("print_job")
    assert_equal PrintDispatch::SUCCEEDED, body["status"]
    assert_equal 100, body["progress"]
    assert_equal "horn.stl", body["filename"]
    assert body["remote_ref"].to_s.start_with?("mock-")
  end

  test "contributor and viewer cannot enqueue a print job" do
    [@contributor, @viewer].each do |user|
      assert_no_enqueued_jobs only: DispatchPrintJob do
        post "/api/v1/print_jobs",
             params: { model_id: @model.id, asset_id: @asset.id, printer_id: @printer.id },
             headers: auth_header(user),
             as: :json
      end
      assert_response :forbidden
    end
    assert_equal 0, PrintDispatch.count
  end

  test "print history is private to the requester" do
    job = PrintDispatch.create!(
      library: @library,
      printer: @printer,
      vibe_model: @model,
      asset: @asset,
      requested_by: @owner,
      status: PrintDispatch::SUCCEEDED,
      filename: @asset.filename
    )
    other = PrintDispatch.create!(
      library: @library,
      printer: @printer,
      vibe_model: @model,
      asset: @asset,
      requested_by: @contributor,
      status: PrintDispatch::SUCCEEDED,
      filename: @asset.filename
    )

    get "/api/v1/print_jobs", headers: auth_header(@owner)
    assert_response :success
    ids = response.parsed_body.fetch("print_jobs").map { |row| row["id"] }
    assert_includes ids, job.id
    refute_includes ids, other.id

    get "/api/v1/print_jobs/#{other.id}", headers: auth_header(@owner)
    assert_response :not_found

    get "/api/v1/print_jobs", headers: auth_header(@contributor)
    assert_response :success
    contrib_ids = response.parsed_body.fetch("print_jobs").map { |row| row["id"] }
    assert_equal [other.id], contrib_ids

    post "/api/v1/print_jobs/#{job.id}/cancel", headers: auth_header(@contributor), as: :json
    assert_response :not_found
  end

  test "disabled printer is rejected without talking to an adapter" do
    @printer.update!(enabled: false)
    assert_no_enqueued_jobs only: DispatchPrintJob do
      post "/api/v1/print_jobs",
           params: { model_id: @model.id, asset_id: @asset.id, printer_id: @printer.id },
           headers: auth_header(@owner),
           as: :json
    end
    assert_response :unprocessable_entity
  end

  test "path jail rejects a file that escapes the library" do
    escaped = @model.assets.create!(relative_path: "../outside.stl", filename: "outside.stl", kind: "stl")
    File.write(@root.join("outside.stl"), "solid escape\nendsolid escape\n")

    assert_no_enqueued_jobs only: DispatchPrintJob do
      post "/api/v1/print_jobs",
           params: { model_id: @model.id, asset_id: escaped.id, printer_id: @printer.id },
           headers: auth_header(@owner),
           as: :json
    end
    assert_response :unprocessable_entity
    assert_match(/invalid|escape|path|folder/i, response.parsed_body["details"].to_s)
  end

  test "sdcp adapter fails the job without 502ing the API" do
    sdcp = @library.printers.create!(
      name: "LAN resin",
      host: "127.0.0.1",
      protocol_type: Printer::SDCP,
      enabled: true,
      settings: { "port" => 1 }
    )

    perform_enqueued_jobs only: DispatchPrintJob do
      post "/api/v1/print_jobs",
           params: { model_id: @model.id, asset_id: @asset.id, printer_id: sdcp.id },
           headers: auth_header(@owner),
           as: :json
      assert_response :accepted
      job_id = response.parsed_body.dig("print_job", "id")
      job = PrintDispatch.find(job_id)
      assert_equal PrintDispatch::FAILED, job.status
      assert job.error_message.present?
      assert_match(/unreachable|timed out|refused|SDCP/i, job.error_message)
    end

    get "/api/v1/print_jobs/#{PrintDispatch.order(:id).last.id}", headers: auth_header(@owner)
    assert_response :success
    shown = response.parsed_body.fetch("print_job")
    assert_equal PrintDispatch::FAILED, shown["status"]
    assert shown["error_message"].present?
    assert shown["retryable"]
  end

  test "stubbed sdcp printer succeeds through the API" do
    sdcp = @library.printers.create!(
      name: "Stub resin",
      host: "10.0.0.40",
      protocol_type: Printer::SDCP,
      enabled: true,
      settings: { "stub" => true, "mainboard_id" => "board1" }
    )

    perform_enqueued_jobs only: DispatchPrintJob do
      post "/api/v1/print_jobs",
           params: { model_id: @model.id, asset_id: @asset.id, printer_id: sdcp.id },
           headers: auth_header(@owner),
           as: :json
      assert_response :accepted
    end

    job = PrintDispatch.order(:id).last
    assert_equal PrintDispatch::SUCCEEDED, job.status
    assert_nil job.error_message
    assert job.remote_ref.to_s.start_with?("sdcp-")
  end

  test "owner can retry a failed job" do
    job = PrintDispatch.create!(
      library: @library,
      printer: @printer,
      vibe_model: @model,
      asset: @asset,
      requested_by: @owner,
      status: PrintDispatch::FAILED,
      error_message: "SDCP printer is busy (Ack=1)",
      filename: @asset.filename,
      protocol_type: Printer::MOCK
    )

    perform_enqueued_jobs only: DispatchPrintJob do
      post "/api/v1/print_jobs/#{job.id}/retry", headers: auth_header(@owner), as: :json
      assert_response :accepted
      body = response.parsed_body.fetch("print_job")
      assert_equal PrintDispatch::QUEUED, body["status"]
      assert_nil body["error_message"]
      refute body["retryable"]
    end

    job.reload
    assert_equal PrintDispatch::SUCCEEDED, job.status
    assert_nil job.error_message
  end

  test "retry is owner-only and only for failed or cancelled jobs" do
    job = PrintDispatch.create!(
      library: @library,
      printer: @printer,
      vibe_model: @model,
      asset: @asset,
      requested_by: @owner,
      status: PrintDispatch::FAILED,
      error_message: "boom",
      filename: @asset.filename
    )
    contrib_job = PrintDispatch.create!(
      library: @library,
      printer: @printer,
      vibe_model: @model,
      asset: @asset,
      requested_by: @contributor,
      status: PrintDispatch::FAILED,
      error_message: "boom",
      filename: @asset.filename
    )

    post "/api/v1/print_jobs/#{job.id}/retry", headers: auth_header(@contributor), as: :json
    assert_response :not_found
    assert_equal PrintDispatch::FAILED, job.reload.status

    post "/api/v1/print_jobs/#{contrib_job.id}/retry", headers: auth_header(@contributor), as: :json
    assert_response :forbidden
    assert_equal PrintDispatch::FAILED, contrib_job.reload.status

    job.update!(status: PrintDispatch::SUCCEEDED, error_message: nil, progress: 100)
    post "/api/v1/print_jobs/#{job.id}/retry", headers: auth_header(@owner), as: :json
    assert_response :conflict
    assert_equal "not_retryable", response.parsed_body["error"]
  end

  test "create printer rejects invalid host and protocol" do
    post "/api/v1/printers",
         params: { library_id: @library.id, name: "URL", host: "http://10.0.0.8", protocol_type: "sdcp" },
         headers: auth_header(@owner),
         as: :json
    assert_response :unprocessable_entity

    post "/api/v1/printers",
         params: { library_id: @library.id, name: "Moon", host: "10.0.0.8", protocol_type: "moonraker" },
         headers: auth_header(@owner),
         as: :json
    assert_response :unprocessable_entity

    post "/api/v1/printers",
         params: {
           library_id: @library.id,
           name: "Saturn",
           host: "10.0.0.8",
           protocol_type: "SDCP",
           enabled: true,
           settings: { port: 3030, token: "lan" }
         },
         headers: auth_header(@owner),
         as: :json
    assert_response :created
    body = response.parsed_body.fetch("printer")
    assert_equal Printer::SDCP, body["protocol_type"]
    assert_equal "10.0.0.8", body["host"]
    assert_equal 3030, body.dig("settings", "port")
  end

  test "requester can cancel an active job" do
    job = PrintDispatch.create!(
      library: @library,
      printer: @printer,
      vibe_model: @model,
      asset: @asset,
      requested_by: @contributor,
      status: PrintDispatch::QUEUED,
      filename: @asset.filename
    )

    post "/api/v1/print_jobs/#{job.id}/cancel", headers: auth_header(@contributor), as: :json
    assert_response :success
    assert_equal PrintDispatch::CANCELLED, job.reload.status
  end

  test "me payload exposes print capabilities" do
    get "/api/v1/me", headers: auth_header(@owner)
    assert_response :success
    assert response.parsed_body.dig("user", "can_print")
    assert response.parsed_body.dig("user", "can_manage_printers")

    get "/api/v1/me", headers: auth_header(@viewer)
    assert_response :success
    refute response.parsed_body.dig("user", "can_print")
    refute response.parsed_body.dig("user", "can_merge")
    refute response.parsed_body.dig("user", "can_manage_printers")
    refute response.parsed_body.dig("user", "can_upload")

    get "/api/v1/me", headers: auth_header(@contributor)
    assert_response :success
    refute response.parsed_body.dig("user", "can_print")
    assert response.parsed_body.dig("user", "can_merge")
  end
end
