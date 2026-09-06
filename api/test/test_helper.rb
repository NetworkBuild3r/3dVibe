ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    include ActiveSupport::Testing::TimeHelpers

    setup do
      SearchIndexBuffer.reset!
      MeilisearchClient.reset_health_cache!
      CoverPacer.reset!
    end

    def fixture_library_root
      Rails.root.join("test/fixtures/files/library").to_s
    end

    def create_owner!(email: "owner@example.test", password: "secret123")
      User.create!(email: email, display_name: "Owner", password: password, password_confirmation: password)
    end

    def create_user!(email:, password: "secret123", display_name: nil)
      User.create!(
        email: email,
        display_name: display_name || email.split("@").first,
        password: password,
        password_confirmation: password
      )
    end

    def auth_header(user)
      token = user.access_tokens.create!(expires_at: 1.day.from_now)
      { "Authorization" => "Bearer #{token.token}" }
    end

    CUBE_FACES = [
      [[0.0, 0.0, 0.0], [1.0, 0.0, 0.0], [1.0, 1.0, 0.0]],
      [[0.0, 0.0, 0.0], [1.0, 1.0, 0.0], [0.0, 1.0, 0.0]],
      [[0.0, 0.0, 1.0], [1.0, 1.0, 1.0], [1.0, 0.0, 1.0]],
      [[0.0, 0.0, 1.0], [0.0, 1.0, 1.0], [1.0, 1.0, 1.0]],
      [[0.0, 0.0, 0.0], [0.0, 1.0, 1.0], [0.0, 1.0, 0.0]],
      [[0.0, 0.0, 0.0], [0.0, 0.0, 1.0], [0.0, 1.0, 1.0]],
      [[1.0, 0.0, 0.0], [1.0, 1.0, 0.0], [1.0, 1.0, 1.0]],
      [[1.0, 0.0, 0.0], [1.0, 1.0, 1.0], [1.0, 0.0, 1.0]],
      [[0.0, 0.0, 0.0], [1.0, 0.0, 1.0], [1.0, 0.0, 0.0]],
      [[0.0, 0.0, 0.0], [0.0, 0.0, 1.0], [1.0, 0.0, 1.0]],
      [[0.0, 1.0, 0.0], [1.0, 1.0, 0.0], [1.0, 1.0, 1.0]],
      [[0.0, 1.0, 0.0], [1.0, 1.0, 1.0], [0.0, 1.0, 1.0]]
    ].freeze

    TETRA_FACES = [
      [[0.0, 0.0, 0.0], [1.0, 0.0, 0.0], [0.5, 0.8, 0.0]],
      [[0.0, 0.0, 0.0], [1.0, 0.0, 0.0], [0.5, 0.3, 0.9]],
      [[1.0, 0.0, 0.0], [0.5, 0.8, 0.0], [0.5, 0.3, 0.9]],
      [[0.5, 0.8, 0.0], [0.0, 0.0, 0.0], [0.5, 0.3, 0.9]]
    ].freeze

    def write_ascii_stl(path, faces = CUBE_FACES, name: "mesh")
      File.open(path, "w") do |io|
        io.puts "solid #{name}"
        faces.each do |tri|
          io.puts "  facet normal 0 0 0"
          io.puts "    outer loop"
          tri.each { |x, y, z| io.puts "      vertex #{x} #{y} #{z}" }
          io.puts "    endloop"
          io.puts "  endfacet"
        end
        io.puts "endsolid #{name}"
      end
    end

    def write_binary_stl(path, faces = CUBE_FACES)
      File.open(path, "wb") do |io|
        io.write("binary mesh".ljust(80, "\0"))
        io.write([faces.size].pack("V"))
        faces.each do |tri|
          io.write(([0.0, 0.0, 0.0] + tri.flatten).pack("e12") + [0].pack("v"))
        end
      end
    end

    def write_obj(path, faces = CUBE_FACES)
      verts = []
      index = {}
      face_lines = faces.map do |tri|
        ids = tri.map do |pt|
          key = pt.map { |n| n.round(6) }
          index[key] ||= begin
            verts << pt
            verts.size
          end
        end
        "f #{ids.join(" ")}"
      end
      lines = verts.map { |x, y, z| "v #{x} #{y} #{z}" } + face_lines
      File.write(path, "#{lines.join("\n")}\n")
    end

    def write_3mf(path, faces = CUBE_FACES)
      require "zip"
      verts = []
      index = {}
      tris = faces.map do |tri|
        tri.map do |pt|
          key = pt.map { |n| n.round(6) }
          index[key] ||= begin
            verts << pt
            verts.size - 1
          end
        end
      end
      vertex_xml = verts.map { |x, y, z| %(<vertex x="#{x}" y="#{y}" z="#{z}"/>) }.join
      tri_xml = tris.map { |a, b, c| %(<triangle v1="#{a}" v2="#{b}" v3="#{c}"/>) }.join
      xml = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
          <resources>
            <object id="1" type="model">
              <mesh>
                <vertices>#{vertex_xml}</vertices>
                <triangles>#{tri_xml}</triangles>
              </mesh>
            </object>
          </resources>
          <build><item objectid="1"/></build>
        </model>
      XML
      Zip::File.open(path, Zip::File::CREATE) do |zip|
        zip.get_output_stream("[Content_Types].xml") { |io| io.write("<Types></Types>") }
        zip.get_output_stream("3D/3dmodel.model") { |io| io.write(xml) }
      end
    end

    def transformed_faces(faces, scale: 1.0, offset: [0.0, 0.0, 0.0])
      faces.map do |tri|
        tri.map { |x, y, z| [x * scale + offset[0], y * scale + offset[1], z * scale + offset[2]] }
      end
    end
  end
end
