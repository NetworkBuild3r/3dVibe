import { describe, expect, it } from "vitest";
import type { Creator, ModelCard } from "./types";
import {
  allChipActive,
  applyCatalogParams,
  catalogQuery,
  columnCount,
  creatorDisplayName,
  emptyLibraryCopy,
  engineStatus,
  facetCreators,
  facetTags,
  friendDisplayName,
  galleryFilterClearParams,
  hasActiveFilters,
  headerCountLabel,
  nextGalleryHasMore,
  readDensity,
  readGalleryFilters,
  searchPillLabel,
  truncateUploaderLabel,
  uploaderSegment,
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
      hasCover: true,
      uploadedBy: ""
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
    expect(emptyLibraryCopy({ q: "", creator: "", tag: "", hasCover: false, uploadedBy: "" }).copy).toBe(
      "Scan the NFS mount to index folders."
    );
    expect(emptyLibraryCopy({ q: "nope", creator: "", tag: "", hasCover: false, uploadedBy: "" })).toEqual({
      copy: "No models match these filters.",
      clearFilters: true
    });
    expect(emptyLibraryCopy({ q: "", creator: "", tag: "", hasCover: true, uploadedBy: "" }).copy).toMatch(
      /ready covers/
    );
  });

  it("treats search q as an active filter for All / Clear", () => {
    const searchOnly = readGalleryFilters(new URLSearchParams("q=hero"));
    const chipsOnly = readGalleryFilters(new URLSearchParams("tag=stl"));
    const idle = readGalleryFilters(new URLSearchParams());
    expect(allChipActive(searchOnly)).toBe(false);
    expect(allChipActive(chipsOnly)).toBe(false);
    expect(allChipActive(idle)).toBe(true);
    expect(searchPillLabel(searchOnly)).toBe("hero");
    expect(searchPillLabel({ q: "  " })).toBe("");
    expect(galleryFilterClearParams()).toEqual({
      q: null,
      tag: null,
      creator: null,
      cover: null,
      uploaded_by: null
    });
  });

  it("halts infinite-scroll paging after a failed page", () => {
    expect(nextGalleryHasMore({ ok: true, hasMore: true })).toBe(true);
    expect(nextGalleryHasMore({ ok: true, hasMore: false })).toBe(false);
    expect(nextGalleryHasMore({ ok: false })).toBe(false);
  });

  it("defaults density to comfortable", () => {
    expect(readDensity({ getItem: () => null })).toBe("comfortable");
    expect(readDensity({ getItem: () => "compact" })).toBe("compact");
    expect(columnCount(700, "comfortable")).toBeGreaterThanOrEqual(2);
  });
});

describe("uploader filter bind", () => {
  const members = [
    { id: 4, display_name: "Pal" },
    { id: 7, display_name: "Very Long Friend Display Name" }
  ];

  it("reads Everyone / Mine / Friend URL params and maps catalog query", () => {
    const everyone = readGalleryFilters(new URLSearchParams());
    const mine = readGalleryFilters(new URLSearchParams("uploaded_by=me&tag=stl"));
    const friend = readGalleryFilters(new URLSearchParams("uploaded_by=4&q=hero"));
    const unknown = readGalleryFilters(new URLSearchParams("uploaded_by=friend"));

    expect(everyone.uploadedBy).toBe("");
    expect(uploaderSegment(everyone)).toBe("everyone");
    expect(catalogQuery(everyone)).toEqual({});
    expect(applyCatalogParams(new URLSearchParams(), catalogQuery(everyone)).has("uploaded_by")).toBe(false);

    expect(mine.uploadedBy).toBe("me");
    expect(uploaderSegment(mine)).toBe("mine");
    expect(hasActiveFilters(mine)).toBe(true);
    expect(allChipActive(mine)).toBe(false);
    expect(usesSearchEndpoint(mine)).toBe(false);
    expect(catalogQuery(mine)).toEqual({ tag: "stl", uploaded_by: "me" });

    expect(friend.uploadedBy).toBe("4");
    expect(uploaderSegment(friend)).toBe("friend");
    expect(usesSearchEndpoint(friend)).toBe(true);
    expect(catalogQuery(friend)).toEqual({ q: "hero", uploaded_by: "4" });

    expect(unknown.uploadedBy).toBe("friend");
    expect(uploaderSegment(unknown)).toBe("friend");
    expect(catalogQuery(unknown)).toEqual({ uploaded_by: "friend" });
    expect(applyCatalogParams(new URLSearchParams(), catalogQuery(unknown)).get("uploaded_by")).toBe("friend");
  });

  it("clears uploaded_by with All / Clear All and keeps other chips when only the segment changes", () => {
    expect(galleryFilterClearParams().uploaded_by).toBeNull();
    const creatorPlusMine = readGalleryFilters(new URLSearchParams("creator=packed-minis&uploaded_by=me"));
    const afterEveryone = { ...creatorPlusMine, uploadedBy: "" };
    expect(catalogQuery(creatorPlusMine)).toEqual({ creator_slug: "packed-minis", uploaded_by: "me" });
    expect(catalogQuery(afterEveryone)).toEqual({ creator_slug: "packed-minis" });
  });

  it("uses Mine / Friend empty copy and does not invent a friend name", () => {
    expect(emptyLibraryCopy({ q: "", creator: "", tag: "", hasCover: false, uploadedBy: "me" })).toEqual({
      copy: "Nothing you’ve uploaded yet. NFS scans without an uploader stay under Everyone.",
      clearFilters: true
    });
    expect(
      emptyLibraryCopy({ q: "", creator: "", tag: "", hasCover: false, uploadedBy: "4" }, { members })
    ).toEqual({
      copy: "No uploads from Pal yet.",
      clearFilters: true
    });
    expect(emptyLibraryCopy({ q: "", creator: "", tag: "", hasCover: false, uploadedBy: "999" }, { members })).toEqual({
      copy: "No models match these filters.",
      clearFilters: true
    });
    expect(friendDisplayName("4", members)).toBe("Pal");
    expect(friendDisplayName("me", members)).toBe("");
    expect(friendDisplayName("999", members)).toBe("");
    expect(truncateUploaderLabel("Pal")).toBe("Pal");
    expect(truncateUploaderLabel("Very Long Friend Display Name")).toBe("Very Long Friend…");
  });
});
