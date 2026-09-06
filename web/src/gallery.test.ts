import { describe, expect, it } from "vitest";
import type { Creator, ModelCard } from "./api";
import {
  applyCatalogParams,
  catalogQuery,
  columnCount,
  creatorDisplayName,
  emptyLibraryCopy,
  engineStatus,
  facetCreators,
  facetTags,
  hasActiveFilters,
  headerCountLabel,
  readDensity,
  readGalleryFilters,
  usesSearchEndpoint
} from "./gallery";

const creators: Creator[] = [
  { id: 1, slug: "packed-minis", name: "Packed Minis", model_count: 4 },
  { id: 2, slug: "signal-horn", name: "Signal Horn", model_count: 1 }
];

const models: ModelCard[] = [
  {
    id: 9,
    title: "Hero",
    folder_name: "hero",
    synopsis: null,
    asset_count: 1,
    byte_size: 12,
    library_id: 1,
    library_name: "Studio",
    tags: ["stl"],
    updated_at: "2026-09-06T00:00:00Z",
    creator: { id: 1, slug: "packed-minis", name: "Packed Minis" }
  }
];

describe("gallery URL and API bind", () => {
  it("reads sticky chip URL params", () => {
    const filters = readGalleryFilters(
      new URLSearchParams("q=hero&creator=packed-minis&tag=stl&cover=1")
    );
    expect(filters).toEqual({
      q: "hero",
      creator: "packed-minis",
      tag: "stl",
      hasCover: true
    });
    expect(hasActiveFilters(filters)).toBe(true);
    expect(usesSearchEndpoint(filters)).toBe(true);
  });

  it("sends chip-only filters to /models (no q, no cursor on search)", () => {
    const filters = readGalleryFilters(new URLSearchParams("creator=packed-minis&cover=1"));
    expect(usesSearchEndpoint(filters)).toBe(false);
    expect(catalogQuery(filters)).toEqual({
      creator_slug: "packed-minis",
      has_cover: true
    });
  });

  it("maps ?cover=1 to has_cover=true and never client-filters covers", () => {
    const query = catalogQuery(readGalleryFilters(new URLSearchParams("cover=1")));
    expect(query).toEqual({ has_cover: true });
    const params = applyCatalogParams(new URLSearchParams(), query);
    expect(params.get("has_cover")).toBe("true");
    expect(params.has("cursor")).toBe(false);
    expect(params.has("q")).toBe(false);
  });

  it("sends q to /search with offset params, not a model-id cursor", () => {
    const query = catalogQuery(readGalleryFilters(new URLSearchParams("q=hero&tag=stl")));
    expect(usesSearchEndpoint(readGalleryFilters(new URLSearchParams("q=hero")))).toBe(true);
    const params = applyCatalogParams(new URLSearchParams({ offset: "0", limit: "48" }), query);
    expect(params.get("q")).toBe("hero");
    expect(params.get("tag")).toBe("stl");
    expect(params.has("cursor")).toBe(false);
  });
});

describe("facets and empty states", () => {
  it("joins creator facets to names, never a raw slug or Unknown creator", () => {
    const options = facetCreators(
      { creator_slug: { "packed-minis": 4, "signal-horn": 1 } },
      creators,
      models
    );
    expect(options.map((item) => item.name)).toEqual(["Packed Minis", "Signal Horn"]);
    expect(creatorDisplayName("packed-minis", creators, models)).toBe("Packed Minis");
    expect(creatorDisplayName("missing", creators, models)).toBe("");
    expect(facetTags({ tags: { stl: 3, zip: 1 } }).map((item) => item.name)).toEqual(["stl", "zip"]);
  });

  it("labels capped fallback totals as a floor", () => {
    expect(headerCountLabel({ filtered: true, count: 250, capped: true })).toBe("at least 250 matches");
    expect(headerCountLabel({ filtered: false, count: 12 })).toBe("12 models");
    expect(engineStatus("postgres", true, true)).toBe("postgres fallback · count is a floor");
  });

  it("uses the states-kit empty copy", () => {
    expect(emptyLibraryCopy({ q: "", creator: "", tag: "", hasCover: false }).copy).toBe(
      "Scan the NFS mount to index folders."
    );
    expect(emptyLibraryCopy({ q: "nope", creator: "", tag: "", hasCover: false })).toEqual({
      copy: "No models match these filters.",
      clearFilters: true
    });
    expect(emptyLibraryCopy({ q: "", creator: "", tag: "", hasCover: true }).copy).toMatch(/ready covers/);
  });

  it("defaults density to comfortable", () => {
    expect(readDensity({ getItem: () => null })).toBe("comfortable");
    expect(readDensity({ getItem: () => "compact" })).toBe("compact");
    expect(columnCount(700, "comfortable")).toBeGreaterThanOrEqual(2);
  });
});
