import type { Creator, ModelCard } from "./api";

export type GalleryDensity = "comfortable" | "compact";

export type GalleryFilters = {
  q: string;
  creator: string;
  tag: string;
  hasCover: boolean;
};

export type CatalogFacets = {
  tags?: Record<string, number>;
  creator_slug?: Record<string, number>;
  cover_status?: Record<string, number>;
  has_cover?: Record<string, number>;
  has_preview?: Record<string, number>;
};

export type CatalogQuery = {
  q?: string;
  creator_slug?: string;
  tag?: string;
  has_cover?: boolean;
  cover_status?: string;
};

export type FacetCreator = { slug: string; name: string; count: number };
export type FacetTag = { name: string; count: number };

export const DENSITY_STORAGE_KEY = "vibe.gallery.density";
export const PAGE_SIZE = 48;
export const SEARCH_DEBOUNCE_MS = 280;

export function readGalleryFilters(params: URLSearchParams): GalleryFilters {
  return {
    q: params.get("q") || "",
    creator: params.get("creator") || "",
    tag: params.get("tag") || "",
    hasCover: params.get("cover") === "1"
  };
}

export function hasChipFilters(filters: Pick<GalleryFilters, "creator" | "tag" | "hasCover">): boolean {
  return Boolean(filters.tag || filters.creator || filters.hasCover);
}

export function hasActiveFilters(filters: GalleryFilters): boolean {
  return Boolean(filters.q.trim() || hasChipFilters(filters));
}

/** Text `q` uses /search (offset). Unfiltered + chip-only stay on /models (cursor). */
export function usesSearchEndpoint(filters: GalleryFilters): boolean {
  return Boolean(filters.q.trim());
}

export function catalogQuery(filters: GalleryFilters): CatalogQuery {
  const query: CatalogQuery = {};
  const q = filters.q.trim();
  if (q) query.q = q;
  if (filters.creator) query.creator_slug = filters.creator;
  if (filters.tag) query.tag = filters.tag;
  if (filters.hasCover) query.has_cover = true;
  return query;
}

export function applyCatalogParams(params: URLSearchParams, query: CatalogQuery): URLSearchParams {
  if (query.q) params.set("q", query.q);
  if (query.creator_slug) params.set("creator_slug", query.creator_slug);
  if (query.tag) params.set("tag", query.tag);
  if (query.has_cover === true) params.set("has_cover", "true");
  if (query.has_cover === false) params.set("has_cover", "false");
  if (query.cover_status) params.set("cover_status", query.cover_status);
  return params;
}

export function creatorDisplayName(
  slug: string,
  creators: Creator[],
  models: ModelCard[] = []
): string {
  const listed = creators.find((item) => item.slug === slug);
  if (listed?.name) return listed.name;
  const fromCard = models.find((item) => item.creator?.slug === slug)?.creator?.name;
  return fromCard || "";
}

export function facetCreators(
  facets: CatalogFacets | undefined,
  creators: Creator[],
  models: ModelCard[] = []
): FacetCreator[] {
  const counts = { ...(facets?.creator_slug || {}) };
  const nameBySlug = new Map<string, string>();
  creators.forEach((item) => {
    nameBySlug.set(item.slug, item.name);
    if (counts[item.slug] == null && item.model_count != null) counts[item.slug] = item.model_count;
  });
  models.forEach((item) => {
    if (item.creator && !nameBySlug.has(item.creator.slug)) {
      nameBySlug.set(item.creator.slug, item.creator.name);
    }
  });
  return Object.entries(counts)
    .map(([slug, count]) => ({
      slug,
      name: nameBySlug.get(slug) || "",
      count
    }))
    .filter((item) => item.name)
    .sort((a, b) => a.name.localeCompare(b.name));
}

export function facetTags(facets: CatalogFacets | undefined): FacetTag[] {
  return Object.entries(facets?.tags || {})
    .map(([name, count]) => ({ name, count }))
    .sort((a, b) => a.name.localeCompare(b.name));
}

export function headerCountLabel(options: {
  filtered: boolean;
  count: number | null;
  capped?: boolean;
}): string | null {
  if (options.count == null) return null;
  const n = options.count.toLocaleString();
  if (options.filtered) {
    const unit = options.count === 1 ? "match" : "matches";
    return options.capped ? `at least ${n} ${unit}` : `${n} ${unit}`;
  }
  return `${n} model${options.count === 1 ? "" : "s"}`;
}

export function engineStatus(engine: string, fallback: boolean, capped: boolean): string {
  if (!engine) return "";
  const label = fallback ? `${engine} fallback` : engine;
  return capped ? `${label} · count is a floor` : label;
}

export function emptyLibraryCopy(filters: GalleryFilters): {
  copy: string;
  clearFilters: boolean;
} {
  if (filters.hasCover && !filters.q.trim() && !filters.tag && !filters.creator) {
    return {
      copy: "No ready covers yet. Unscanned or pending models stay on the checker until Rendering writes back.",
      clearFilters: true
    };
  }
  if (hasActiveFilters(filters)) {
    return { copy: "No models match these filters.", clearFilters: true };
  }
  return { copy: "Scan the NFS mount to index folders.", clearFilters: false };
}

export function readDensity(storage: Pick<Storage, "getItem"> | null | undefined): GalleryDensity {
  try {
    return storage?.getItem(DENSITY_STORAGE_KEY) === "compact" ? "compact" : "comfortable";
  } catch {
    return "comfortable";
  }
}

export function writeDensity(storage: Pick<Storage, "setItem"> | null | undefined, density: GalleryDensity) {
  try {
    storage?.setItem(DENSITY_STORAGE_KEY, density);
  } catch {
    /* ignore quota / private mode */
  }
}

export function gridMetrics(density: GalleryDensity) {
  return density === "compact"
    ? { minColumn: 160, gap: 12, estimateRow: 248 }
    : { minColumn: 220, gap: 20, estimateRow: 328 };
}

export function columnCount(width: number, density: GalleryDensity): number {
  const { minColumn, gap } = gridMetrics(density);
  if (width <= 0) return 1;
  return Math.max(1, Math.floor((width + gap) / (minColumn + gap)));
}
