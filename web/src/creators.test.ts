import { describe, expect, it } from "vitest";
import type { Creator } from "./api";
import {
  creatorHref,
  creatorsIndexHref,
  emptyCreatorModelsCopy,
  emptyCreatorsIndexCopy,
  filterCreators,
  isMissingCreatorError,
  libraryHrefForCreator,
  missingCreatorCopy,
  modelCountLabel,
  modelCountOf,
  mosaicSlots
} from "./creators";

const creators: Creator[] = [
  { id: 1, slug: "packed-minis", name: "Packed Minis", model_count: 4 },
  { id: 2, slug: "signal-horn", name: "Signal Horn", model_count: 1 }
];

describe("creator pack homes", () => {
  it("jumps to Library with ?creator= so sticky chips bind the pill", () => {
    expect(libraryHrefForCreator("packed-minis")).toBe("/?creator=packed-minis");
    expect(libraryHrefForCreator("mz4250")).toBe("/?creator=mz4250");
  });

  it("keeps pack-home links on /creators/:slug and preserves search q", () => {
    expect(creatorsIndexHref()).toBe("/creators");
    expect(creatorsIndexHref(" mini ")).toBe("/creators?q=mini");
    expect(creatorHref("packed-minis")).toBe("/creators/packed-minis");
    expect(creatorHref("packed-minis", " mini ")).toBe("/creators/packed-minis?q=mini");
  });

  it("filters the index by name or slug and never invents Unknown creator", () => {
    expect(filterCreators(creators, "").map((item) => item.slug)).toEqual(["packed-minis", "signal-horn"]);
    expect(filterCreators(creators, "PACK").map((item) => item.name)).toEqual(["Packed Minis"]);
    expect(filterCreators(creators, "horn").map((item) => item.slug)).toEqual(["signal-horn"]);
    expect(filterCreators(creators, "missing")).toEqual([]);
  });

  it("labels model counts from the creators API", () => {
    expect(modelCountOf(creators[0])).toBe(4);
    expect(modelCountOf({ slug: "x", name: "X", id: 9 })).toBe(0);
    expect(modelCountLabel(0)).toBe("0 models");
    expect(modelCountLabel(1)).toBe("1 model");
    expect(modelCountLabel(12)).toBe("12 models");
  });

  it("pads cover mosaics to a 2×2", () => {
    expect(mosaicSlots(["a", "b"]).map((item) => item ?? null)).toEqual(["a", "b", null, null]);
    expect(mosaicSlots([1, 2, 3, 4, 5])).toEqual([1, 2, 3, 4]);
  });

  it("uses pack-home empty and missing copy", () => {
    expect(emptyCreatorsIndexCopy("").copy).toMatch(/No creators yet/);
    expect(emptyCreatorsIndexCopy("nope")).toEqual({ copy: "No creators match that search." });
    expect(emptyCreatorModelsCopy("packed-minis")).toEqual({
      copy: "This creator has no models yet.",
      ctaTo: "/?creator=packed-minis",
      ctaLabel: "View in Library"
    });
    expect(missingCreatorCopy().ctaTo).toBe("/creators");
  });

  it("treats API not_found / 404 as a missing pack home", () => {
    expect(isMissingCreatorError({ status: 404, message: "not_found" })).toBe(true);
    expect(isMissingCreatorError(new Error("not_found"))).toBe(true);
    expect(isMissingCreatorError(new Error("Request failed (404)"))).toBe(true);
    expect(isMissingCreatorError(new Error("Could not load creator"))).toBe(false);
  });
});
