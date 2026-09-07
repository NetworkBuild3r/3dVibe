import { describe, expect, it } from "vitest";
import { resolveDuplicateLibraryId } from "./duplicates";
import {
  canReadLibraryOps,
  canScanLibraries,
  isWritableLibrary,
  persistLibraryId,
  scanTargetLibrary,
  selectedLibrary,
  writableLibraries
} from "./library";

const studio = { id: 1, name: "Studio", can_upload: true, can_scan: true };
const friends = { id: 2, name: "Friends", can_upload: false, can_scan: false };
const archive = { id: 3, name: "Archive", can_upload: true, can_scan: false };

describe("useLibrary selection helpers", () => {
  it("defaults to libraries[0] only when nothing is selected", () => {
    expect(persistLibraryId([studio, friends], "")).toBe(1);
    expect(persistLibraryId([], "")).toBe("");
  });

  it("keeps the selected id across a list refresh", () => {
    expect(persistLibraryId([studio, friends], 2)).toBe(2);
    expect(persistLibraryId([friends, studio], 2)).toBe(2);
  });

  it("does not clear a selection when the library list is empty", () => {
    expect(persistLibraryId([], 2)).toBe(2);
    expect(selectedLibrary([], 2)).toBeUndefined();
    expect(selectedLibrary([studio, friends], "")).toBeUndefined();
    expect(selectedLibrary([studio, friends], 2)?.name).toBe("Friends");
  });

  it("lets Dupes fall back when the current id is gone; other pickers persist", () => {
    expect(persistLibraryId([studio], 2)).toBe(2);
    expect(
      resolveDuplicateLibraryId({
        libraries: [studio],
        currentId: 2
      })
    ).toBe(1);
    expect(
      resolveDuplicateLibraryId({
        libraries: [studio, friends],
        preferredId: 2,
        currentId: 1
      })
    ).toBe(2);
  });

  it("filters upload to writable libraries only", () => {
    expect(writableLibraries([studio, friends, archive]).map((library) => library.id)).toEqual([1, 3]);
    expect(isWritableLibrary(friends)).toBe(false);
    expect(persistLibraryId(writableLibraries([studio, friends, archive]), "")).toBe(1);
    expect(persistLibraryId(writableLibraries([friends]), "")).toBe("");
  });

  it("points Scan at a can_scan library, else the first row", () => {
    expect(scanTargetLibrary([friends, studio])?.id).toBe(1);
    expect(scanTargetLibrary([friends, archive])?.id).toBe(2);
    expect(scanTargetLibrary([])).toBeUndefined();
  });

  it("keeps Scan chrome owner-gated the same way as today", () => {
    expect(canScanLibraries({ can_invite: true, can_manage_libraries: false })).toBe(true);
    expect(canScanLibraries({ can_invite: false, can_manage_libraries: true })).toBe(true);
    expect(canScanLibraries({ can_invite: false, can_manage_libraries: false })).toBe(false);
    expect(canScanLibraries({ can_invite: false })).toBe(false);
    expect(canScanLibraries(null)).toBe(false);
    expect(canScanLibraries(undefined)).toBe(false);
  });

  it("keeps the ops strip curator-gated, not a new owner-only page", () => {
    expect(canReadLibraryOps({ can_curate: true })).toBe(true);
    expect(canReadLibraryOps({ can_curate: false })).toBe(false);
    expect(canReadLibraryOps(null)).toBe(false);
    expect(canReadLibraryOps(undefined)).toBe(false);
  });
});
