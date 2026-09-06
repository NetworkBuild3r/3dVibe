import { describe, expect, it } from "vitest";
import type { DuplicateGroup, DuplicateMember, ExtractedArchiveAsset } from "./api";
import {
  allMembersMergeable,
  applyExtractedMembers,
  archiveMemberIds,
  archiveMembersToExtract,
  canExtractArchiveMembers,
  EXTRACT_AND_MERGE_COPY,
  EXTRACTING_COPY,
  groupHasArchive,
  isArchiveResident,
  looseAssetIds,
  memberDisplayPath,
  MERGE_UNSUPPORTED_COPY,
  mergePayloadForGroup,
  preferredTargetId
} from "./duplicates";

const archiveMember: DuplicateMember = {
  kind: "archive_member",
  mergeable: false,
  id: 12,
  archive_member_id: 12,
  filename: "foo.stl",
  member_path: "path/foo.stl",
  archive_path: "pack.zip → path/foo.stl",
  parent_filename: "pack.zip",
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

const extracted: ExtractedArchiveAsset[] = [
  {
    archive_member_id: 12,
    asset_id: 99,
    model_id: 7,
    relative_path: "foo.stl",
    filename: "foo.stl",
    mergeable: true
  }
];

describe("duplicate extract bind", () => {
  it("keeps archive members unmergeable until extract", () => {
    expect(archiveMemberIds(group)).toEqual([12]);
    expect(looseAssetIds(group)).toEqual([88]);
    expect(canExtractArchiveMembers(group)).toBe(true);
    expect(allMembersMergeable(group)).toBe(false);
    expect(groupHasArchive(group)).toBe(true);
    expect(MERGE_UNSUPPORTED_COPY).toMatch(/Keep and Dismiss still work/i);
  });

  it("defaults the extract target to the first loose model", () => {
    expect(preferredTargetId(group)).toBe(7);
  });

  it("lists archive members as pack.zip → path for the confirm sheet", () => {
    const rows = archiveMembersToExtract(group);
    expect(rows).toHaveLength(1);
    expect(memberDisplayPath(rows[0])).toBe("pack.zip → path/foo.stl");
  });

  it("uses the design extract-and-merge confirm copy", () => {
    expect(EXTRACT_AND_MERGE_COPY).toBe(
      "Extracts selected files into the library folder (path-jailed), then merges. NFS files are not silent-deleted."
    );
    expect(EXTRACTING_COPY).toBe("Extracting…");
  });

  it("does not offer extract on a terminal group", () => {
    expect(canExtractArchiveMembers({ ...group, status: "merged" })).toBe(false);
  });

  it("turns an extracted member Loose and mergeable without touching the zip row until overlay", () => {
    const next = applyExtractedMembers(group, extracted, { id: 7, title: "Crate", folder_name: "crate" });
    const member = next.members?.find((row) => row.asset_id === 99);
    expect(member).toBeTruthy();
    expect(isArchiveResident(member!)).toBe(false);
    expect(member!.mergeable).toBe(true);
    expect(member!.kind).toBe("asset");
    expect(member!.model_id).toBe(7);
    expect(allMembersMergeable(next)).toBe(true);
    expect(canExtractArchiveMembers(next)).toBe(false);
    expect(archiveMembersToExtract(group)[0].mergeable).toBe(false);
  });

  it("builds a merge payload from on-disk copies only", () => {
    const next = applyExtractedMembers(
      group,
      [{ ...extracted[0], model_id: 4 }],
      { id: 4, title: "Packed", folder_name: "packed" }
    );
    const payload = mergePayloadForGroup(next, 4, "Packed");
    expect(payload.target_id).toBe(4);
    expect(payload.source_ids).toEqual([7]);
    expect(payload.asset_ids).toEqual([88]);
    expect(payload.source_ids).not.toContain(4);
    expect(payload.asset_ids).not.toContain(12);
  });
});
