import type { Creator, ModelCard } from "./api";

export const CREATOR_PAGE_SIZE = 24;
export const MOSAIC_SIZE = 4;

export function libraryHrefForCreator(slug: string): string {
  const params = new URLSearchParams();
  params.set("creator", slug);
  return `/?${params.toString()}`;
}

export function creatorsIndexHref(query?: string): string {
  const q = query?.trim();
  if (!q) return "/creators";
  const params = new URLSearchParams();
  params.set("q", q);
  return `/creators?${params.toString()}`;
}

export function creatorHref(slug: string, query?: string): string {
  const path = `/creators/${encodeURIComponent(slug)}`;
  const q = query?.trim();
  if (!q) return path;
  const params = new URLSearchParams();
  params.set("q", q);
  return `${path}?${params.toString()}`;
}

export function filterCreators(creators: Creator[], query: string): Creator[] {
  const q = query.trim().toLowerCase();
  if (!q) return creators;
  return creators.filter(
    (creator) => creator.name.toLowerCase().includes(q) || creator.slug.toLowerCase().includes(q)
  );
}

export function modelCountOf(creator: Pick<Creator, "model_count">, covers: ModelCard[] = []): number {
  return creator.model_count ?? covers.length;
}

export function modelCountLabel(count: number): string {
  return `${count} model${count === 1 ? "" : "s"}`;
}

export function mosaicSlots<T>(covers: T[], size = MOSAIC_SIZE): Array<T | undefined> {
  return Array.from({ length: size }, (_, index) => covers[index]);
}

export function isMissingCreatorError(err: unknown): boolean {
  if (err && typeof err === "object" && "status" in err && (err as { status?: number }).status === 404) {
    return true;
  }
  const message = err instanceof Error ? err.message : String(err ?? "");
  return message === "not_found" || /not_found|\b404\b/.test(message);
}

export function emptyCreatorsIndexCopy(query: string): {
  copy: string;
  ctaTo?: string;
  ctaLabel?: string;
} {
  if (query.trim()) {
    return { copy: "No creators match that search." };
  }
  return {
    copy: "No creators yet. Scan the library to infer names from folders.",
    ctaTo: "/",
    ctaLabel: "Back to library"
  };
}

export function emptyCreatorModelsCopy(slug: string): {
  copy: string;
  ctaTo: string;
  ctaLabel: string;
} {
  return {
    copy: "This creator has no models yet.",
    ctaTo: libraryHrefForCreator(slug),
    ctaLabel: "View in Library"
  };
}

export function missingCreatorCopy(): {
  copy: string;
  ctaTo: string;
  ctaLabel: string;
} {
  return {
    copy: "This creator is missing or has not been scanned yet.",
    ctaTo: "/creators",
    ctaLabel: "All creators"
  };
}
