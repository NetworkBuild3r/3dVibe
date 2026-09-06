import { describe, expect, it } from "vitest";
import type { DuplicateGroup, DuplicateMember } from "./api";
import {
  archiveMemberIds,
  canExtractArchiveMembers,
  looseAssetIds,
  MERGE_UNSUPPORTED_COPY
} from "./duplicates";

const archiveMember: DuplicateMember = {
  kind: "archive_member",
  mergeable: false,
  id: 12,
  archive_member_id: 12,
  filename: "foo.stl",
  member_path: "path/foo.stl",
  archive_path: "pack.zip → path/foo.stl",
  model_id: 4,
  model_title: "Packed"
};

const looseMember: DuplicateMember = {
  kind: "asset",
  mergeable: true,
  id: 88,
  asset_id: 88,
  filename: "box.stl",
  relative_path: "box.stl",
  model_id: 7,
  model_title: "Crate"
};

const group: DuplicateGroup = {
  id: 3,
  reason: "geometry",
  confidence: "geometry",
  digest: "mesh:v1:abc",
  status: "open",
  filename: "foo.stl",
  byte_size: 20,
  members: [archiveMember, looseMember],
  assets: []
};

describe("duplicate extract bind", () => {
  it("keeps archive members unmergeable until extract", () => {
    expect(archiveMemberIds(group)).toEqual([12]);
    expect(looseAssetIds(group)).toEqual([88]);
    expect(canExtractArchiveMembers(group)).toBe(true);
    expect(MERGE_UNSUPPORTED_COPY).toMatch(/Extract/i);
  });

  it("does not offer extract on a terminal group", () => {
    expect(canExtractArchiveMembers({ ...group, status: "merged" })).toBe(false);
  });
});
