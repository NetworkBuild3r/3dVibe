#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "pathname"
require "zlib"

ROOT = Pathname.new(__dir__).join("library")

STL = <<~STL
  solid part
    facet normal 0 0 1
      outer loop
        vertex 0 0 1
        vertex 20 0 1
        vertex 0 20 1
      endloop
    endfacet
    facet normal 0 0 -1
      outer loop
        vertex 0 0 0
        vertex 0 20 0
        vertex 20 0 0
      endloop
    endfacet
  endsolid part
STL

SAMPLES = [
  ["calibration-cube", "A 20mm gauge cube for first-layer checks.", "cube.stl"],
  ["signal-horn", "Handheld signal horn, one-piece print.", "horn.stl"],
  ["desk-hook", "Under-desk hook for headphones.", "hook.stl"],
  ["cable-comb", "Five-slot cable comb for a small rack.", "comb.stl"],
  ["garden-whistle", "Garden-gate whistle body.", "whistle.stl"]
].freeze

EXTRA = [
  "bearing-jig", "camera-plate", "drawer-latch", "fan-shroud", "glue-stand",
  "hex-tray", "ink-riser", "joystick-cap", "key-clip", "lamp-collar",
  "magnet-jig", "nozzle-rack", "outlet-cover", "phone-sled", "quad-spacer",
  "rail-stop", "spool-guide", "tool-cup", "umbilical-clip", "vent-louver",
  "wrench-hook", "xylophone-mallet", "y-axis-block", "z-stop-flag"
].freeze

def write_folder(name, synopsis, filename)
  dir = ROOT.join(name)
  FileUtils.mkdir_p(dir)
  File.write(dir.join("readme.txt"), synopsis)
  File.write(dir.join(filename), STL)
end

def write_zip(path, entries)
  # Minimal ZIP (stored) so the repo does not need rubyzip at generation time.
  require "stringio"

  local_parts = []
  central_parts = []
  offset = 0

  entries.each do |name, body|
    data = body.b
    crc = Zlib.crc32(data)
    local = +"".b
    # DOS time/date for 2026-01-01 12:00 so zip parsers accept the central directory.
    dos_time = (12 << 11)
    dos_date = 1 | (1 << 5) | ((2026 - 1980) << 9)
    local << [0x04034b50, 20, 0, 0, dos_time, dos_date, crc, data.bytesize, data.bytesize, name.bytesize, 0].pack("VvvvvvVVVvv")
    local << name.b
    local << data
    central = +"".b
    central << [0x02014b50, 20, 20, 0, 0, dos_time, dos_date, crc, data.bytesize, data.bytesize, name.bytesize, 0, 0, 0, 0, 0, offset].pack("VvvvvvvVVVvvvvvVV")
    central << name.b
    local_parts << local
    central_parts << central
    offset += local.bytesize
  end

  locals = local_parts.join
  centrals = central_parts.join
  eocd = [0x06054b50, 0, 0, entries.length, entries.length, centrals.bytesize, locals.bytesize, 0].pack("VvvvvVVv")
  File.binwrite(path, locals + centrals + eocd)
end

FileUtils.rm_rf(ROOT)
FileUtils.mkdir_p(ROOT)

SAMPLES.each { |name, synopsis, file| write_folder(name, synopsis, file) }
EXTRA.each do |name|
  write_folder(name, "Sample fixture folder #{name.tr('-', ' ')}.", "#{name.split('-').first}.stl")
end

# 32x32 teal PNG so archive image preview is visible in the viewer.
PNG_TEAL = ["89504e470d0a1a0a0000000d4948445200000020000000200802000000fc18eda30000002b4944415478da63d0bdb29fa68861d482510b462d18b560d482510b462d18b560d482510b462d182a16000040b0006a82d8eda00000000049454e44ae426082"].pack("H*")

pack = ROOT.join("packed-minis")
FileUtils.mkdir_p(pack)
File.write(pack.join("readme.txt"), "A zip kit with printable members, a nested folder, and a preview still.")
write_zip(
  pack.join("minis.zip"),
  [
    ["hero.stl", STL],
    ["sidekick.stl", STL],
    ["preview/hero.png", PNG_TEAL],
    ["extras/readme.txt", "Packed kit members for archive-tree tests."],
    ["extras/nested/note.txt", "Deeper folder for lazy tree children."]
  ]
)
write_zip(
  pack.join("kit.3mf"),
  [
    ["[Content_Types].xml", "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"></Types>\n"],
    ["3D/3dmodel.model", "<model>packed-minis fixture</model>\n"]
  ]
)
File.binwrite(pack.join("notes.7z"), "not a real 7z; listing is best-effort when 7z is installed\n")

puts "Wrote #{ROOT.children.count} fixture folders into #{ROOT}"
