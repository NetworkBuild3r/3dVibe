import { describe, expect, it } from "vitest";
import { isActiveScan, packsIndexedCount, parseScanStatus, scanChip } from "./ops";

describe("scan progress — INIT-020/SPEC-008", () => {
  it("reads packs_indexed from SPEC-007 ops JSON and labels packs, not models", () => {
    const scan = parseScanStatus({
      status: "running",
      running: true,
      packs_indexed: 2,
      folders_indexed: 2,
      last_pack_path: "Anime/AOT-ErenXArmored",
      phase: "index"
    });
    expect(scan?.packs_indexed).toBe(2);
    expect(scan?.running).toBe(true);
    expect(scan?.last_pack_path).toBe("Anime/AOT-ErenXArmored");
    expect(packsIndexedCount(scan)).toBe(2);
    expect(isActiveScan(scan)).toBe(true);
    const chip = scanChip(scan);
    expect(chip.label).toContain("2 packs");
    expect(chip.label).not.toMatch(/2 models/);
  });

  it("falls back to folders_indexed when packs_indexed is omitted", () => {
    const scan = parseScanStatus({ status: "queued", folders_indexed: 1 });
    expect(packsIndexedCount(scan)).toBe(1);
    expect(scanChip(scan).label).toContain("1 pack");
  });
});
