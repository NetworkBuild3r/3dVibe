import type { Creator, LibraryMember, ModelCard } from "./types";

export type GalleryDensity = "comfortable" | "compact";
export type UploaderSegment = "everyone" | "mine" | "friend";

export type GalleryFilters = {
  q: string;
  creator: string;
  tag: string;
  category: string;
  hasCover: boolean;
  uploadedBy: string;
};

export type FacetCategory = { name: string; count: number };

export type ScanProgress = {
  scanning: boolean;
  packsIndexed: number;
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
  uploaded_by?: string;
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
    category: params.get("category") || "",
    hasCover: params.get("cover") === "1",
    uploadedBy: params.get("uploaded_by") || ""
  };
}

export function hasChipFilters(
  filters: Pick<GalleryFilters, "creator" | "tag" | "category" | "hasCover" | "uploadedBy">
): boolean {
  return Boolean(filters.tag || filters.creator || filters.category || filters.hasCover || filters.uploadedBy);
}

export function hasActiveFilters(filters: GalleryFilters): boolean {
  return Boolean(filters.q.trim() || hasChipFilters(filters));
}

/** All / Clear filters / Clear All must drop search `q` as well as chips. */
export function galleryFilterClearParams(): Record<
  "q" | "tag" | "creator" | "category" | "cover" | "uploaded_by",
  null
> {
  return { q: null, tag: null, creator: null, category: null, cover: null, uploaded_by: null };
}

export function uploaderSegment(filters: Pick<GalleryFilters, "uploadedBy">): UploaderSegment {
  const value = filters.uploadedBy.trim();
  if (!value) return "everyone";
  if (value.toLowerCase() === "me") return "mine";
  return "friend";
}

export function friendDisplayName(
  uploadedBy: string,
  members: Pick<LibraryMember, "id" | "display_name">[] = []
): string {
  if (!/^\d+$/.test(uploadedBy.trim())) return "";
  const id = Number(uploadedBy);
  return members.find((member) => member.id === id)?.display_name || "";
}

export function truncateUploaderLabel(name: string, max = 18): string {
  const trimmed = name.trim();
  if (trimmed.length <= max) return trimmed;
  return `${trimmed.slice(0, Math.max(1, max - 1)).trimEnd()}…`;
}

export function allChipActive(filters: GalleryFilters): boolean {
  return !hasActiveFilters(filters);
}

export function searchPillLabel(filters: Pick<GalleryFilters, "q">): string {
  return filters.q.trim();
}

/** Sentinel / loadMore must stop after a failed page until the user hits Retry. */
export function nextGalleryHasMore(outcome: { ok: true; hasMore: boolean } | { ok: false }): boolean {
  return outcome.ok ? outcome.hasMore : false;
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
  // Category chips filter pack cards locally — GET /models has no category query (INIT-020/SPEC-008).
  if (filters.hasCover) query.has_cover = true;
  if (filters.uploadedBy) query.uploaded_by = filters.uploadedBy;
  return query;
}

export function applyCatalogParams(params: URLSearchParams, query: CatalogQuery): URLSearchParams {
  if (query.q) params.set("q", query.q);
  if (query.creator_slug) params.set("creator_slug", query.creator_slug);
  if (query.tag) params.set("tag", query.tag);
  if (query.has_cover === true) params.set("has_cover", "true");
  if (query.has_cover === false) params.set("has_cover", "false");
  if (query.cover_status) params.set("cover_status", query.cover_status);
  if (query.uploaded_by) params.set("uploaded_by", query.uploaded_by);
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
  return `${n} pack${options.count === 1 ? "" : "s"}`;
}

/** First path segment when API omits category — never invent a mega-category card. */
export function categoryFromCard(model: Pick<ModelCard, "category" | "folder_name">): string {
  const labeled = model.category?.trim();
  if (labeled) return labeled;
  const folder = model.folder_name?.trim() || "";
  const slash = folder.indexOf("/");
  return slash > 0 ? folder.slice(0, slash) : "";
}

export function facetCategories(models: ModelCard[] = []): FacetCategory[] {
  const counts = new Map<string, number>();
  models.forEach((item) => {
    const name = categoryFromCard(item);
    if (!name) return;
    counts.set(name, (counts.get(name) || 0) + 1);
  });
  return [...counts.entries()]
    .map(([name, count]) => ({ name, count }))
    .sort((a, b) => a.name.localeCompare(b.name));
}

export function filterPacksByCategory(models: ModelCard[], category: string): ModelCard[] {
  const selected = category.trim();
  if (!selected) return models;
  return models.filter((item) => categoryFromCard(item) === selected);
}

export function shouldReloadGalleryForScan(prev: ScanProgress, next: ScanProgress): boolean {
  if (next.scanning && next.packsIndexed > prev.packsIndexed) return true;
  if (prev.scanning && !next.scanning) return true;
  return false;
}

export function engineStatus(engine: string, fallback: boolean, capped: boolean): string {
  if (!engine) return "";
  const label = fallback ? `${engine} fallback` : engine;
  return capped ? `${label} · count is a floor` : label;
}

export function emptyLibraryCopy(
  filters: GalleryFilters,
  options: {
    members?: Pick<LibraryMember, "id" | "display_name">[];
    scanning?: boolean;
    packsIndexed?: number;
  } = {}
): {
  copy: string;
  clearFilters: boolean;
} {
  const chipsOnly = !filters.q.trim() && !filters.tag && !filters.creator && !filters.category;
  const segment = uploaderSegment(filters);

  if (segment === "mine" && chipsOnly && !filters.hasCover) {
    return {
      copy: "Nothing you’ve uploaded yet. NFS scans without an uploader stay under Everyone.",
      clearFilters: true
    };
  }
  if (segment === "friend" && chipsOnly && !filters.hasCover) {
    const name = friendDisplayName(filters.uploadedBy, options.members);
    if (name) {
      return { copy: `No uploads from ${name} yet.`, clearFilters: true };
    }
  }
  if (filters.hasCover && chipsOnly && !filters.uploadedBy) {
    return {
      copy: "No ready covers yet. Unscanned or pending models stay on the checker until Rendering writes back.",
      clearFilters: true
    };
  }
  if (filters.category && !filters.q.trim() && !filters.tag && !filters.creator && !filters.hasCover && !filters.uploadedBy) {
    if (options.scanning) {
      return {
        copy: `Scanning… packs in ${filters.category} appear as they’re indexed.`,
        clearFilters: true
      };
    }
    return { copy: `No packs in ${filters.category} yet.`, clearFilters: true };
  }
  if (hasActiveFilters(filters)) {
    return { copy: "No models match these filters.", clearFilters: true };
  }
  if (options.scanning) {
    const n = options.packsIndexed ?? 0;
    return {
      copy:
        n > 0
          ? `Scanning… ${n} pack${n === 1 ? "" : "s"} indexed so far.`
          : "Scanning the library… packs appear as they’re indexed.",
      clearFilters: false
    };
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

const FILE_KIND_TAGS = new Set([
  "stl",
  "obj",
  "3mf",
  "gcode",
  "bgcode",
  "png",
  "jpg",
  "jpeg",
  "webp",
  "gif",
  "zip",
  "7z",
  "rar",
  "json",
  "file"
]);

const WEAK_SHELF_TAGS = new Set([
  "anime",
  "cartoons",
  "cosplay",
  "d-d",
  "d&d",
  "dnd",
  "dc",
  "games",
  "movie-tv",
  "movie",
  "tv",
  "untagged",
  "unknown",
  "anystl",
  "cults3d",
  "gumroad"
]);

/** First useful card chip. File kinds stay searchable; shelf tags lose to a specific keyword. */
export function cardChipTag(tags: string[] | undefined | null): string | null {
  const semantic = (tags || [])
    .map((tag) => tag.trim())
    .filter((tag) => tag && !FILE_KIND_TAGS.has(tag.toLowerCase()));
  const specific = semantic.find((tag) => !WEAK_SHELF_TAGS.has(tag.toLowerCase()));
  return specific || semantic[0] || null;
}

export function columnCount(width: number, density: GalleryDensity): number {
  const { minColumn, gap } = gridMetrics(density);
  if (width <= 0) return 1;
  return Math.max(1, Math.floor((width + gap) / (minColumn + gap)));
}
