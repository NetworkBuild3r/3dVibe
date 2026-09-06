require "test_helper"
require "fileutils"
require "zip"

class ArchiveMembersExtractTest < ActionDispatch::IntegrationTest
  def setup
    @root = Rails.root.join("tmp/extract-api-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(@root.join("packed"))
    Zip::File.open(@root.join("packed/pack.zip"), Zip::File::CREATE) do |zip|
      zip.get_output_stream("path/foo.stl") { |io| io.write("solid foo\nendsolid foo\n") }
      zip.get_output_stream("noise/huge.bin") { |io| io.write("Y" * 32 * 1024) }
    end
    FileUtils.mkdir_p(@root.join("crate"))
    File.write(@root.join("crate/box.stl"), "solid box\nendsolid box\n")

    @owner = create_owner!
    @contributor = create_user!(email: "contrib@example.test")
    @viewer = create_user!(email: "viewer@example.test")
    @library = Library.create!(name: "Extract API", root_path: @root.to_s)
    Membership.create!(user: @owner, library: @library, role: Membership::OWNER)
    Membership.create!(user: @contributor, library: @library, role: Membership::CONTRIBUTOR)
    Membership.create!(user: @viewer, library: @library, role: Membership::VIEWER)
    LibraryScanner.new(@library, budget: ScanBudget.unlimited).scan!
    @member = @library.vibe_models.find_by!(folder_name: "packed").assets.find_by!(filename: "pack.zip")
                      .archive_members.find_by!(internal_path: "path/foo.stl")
    @crate = @library.vibe_models.find_by!(folder_name: "crate")
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  test "POST extract streams one member and returns mergeable asset ids" do
    zip_bytes = File.binread(@root.join("packed/pack.zip"))

    post "/api/v1/archive_members/extract",
         params: { archive_member_ids: [@member.id], target_model_id: @crate.id },
         headers: auth_header(@contributor),
         as: :json
    assert_response :created
    extracted = response.parsed_body.fetch("extracted")
    assert_equal 1, extracted.size
    assert_equal true, extracted.first["mergeable"]
    assert_equal @member.id, extracted.first["archive_member_id"]
    assert_equal @crate.id, extracted.first["model_id"]
    assert response.parsed_body.dig("model", "assets").any? { |asset| asset["id"] == extracted.first["asset_id"] && asset["mergeable"] }
    assert File.file?(@root.join("crate/foo.stl"))
    refute File.exist?(@root.join("crate/huge.bin"))
    refute File.exist?(@root.join("packed/path/foo.stl"))
    assert_equal zip_bytes, File.binread(@root.join("packed/pack.zip"))
  end

  test "POST extract_and_merge extracts then runs ModelComposer" do
    loose = @crate.assets.find_by!(filename: "box.stl")

    post "/api/v1/archive_members/extract_and_merge",
         params: {
           archive_member_ids: [@member.id],
           asset_ids: [loose.id],
           title: "Kit"
         },
         headers: auth_header(@owner),
         as: :json
    assert_response :created
    assert_equal true, response.parsed_body.fetch("extracted").first["mergeable"]
    assert response.parsed_body["merge"]
    folder = response.parsed_body.dig("model", "folder_name")
    assert File.file?(@root.join("#{folder}/foo.stl"))
    assert File.file?(@root.join("#{folder}/crate/box.stl"))
    assert File.file?(@root.join("packed/pack.zip"))
  end

  test "extract rejects jail escape and forbids viewers" do
    post "/api/v1/archive_members/extract",
         params: { archive_member_ids: [@member.id], folder_name: "../etc" },
         headers: auth_header(@owner),
         as: :json
    assert_response :unprocessable_entity
    refute File.exist?(Pathname.new(@root).join("..", "etc"))

    post "/api/v1/archive_members/extract",
         params: { archive_member_ids: [@member.id], title: "Nope" },
         headers: auth_header(@viewer),
         as: :json
    assert_response :forbidden
    refute @library.vibe_models.exists?(folder_name: "nope")
  end
end
