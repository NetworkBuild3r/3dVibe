import type { CoverStatus, ModelCard } from "./types";

export type CoverVisual = "image" | "shimmer" | "placeholder";

export type CoverFields = Pick<
  ModelCard,
  "cover_status" | "cover_url" | "cover_lqip_url" | "cover_placeholder"
>;

export function coverStatusOf(model: CoverFields): CoverStatus {
  if (model.cover_status) return model.cover_status;
  if (model.cover_url && model.cover_placeholder === false) return "ready";
  if (model.cover_placeholder) return "missing";
  return "missing";
}

export function coverVisual(model: CoverFields): CoverVisual {
  const status = coverStatusOf(model);
  if (status === "ready" && (model.cover_url || model.cover_lqip_url)) return "image";
  if (status === "pending") return "shimmer";
  return "placeholder";
}

export function resolveCoverUrl(url: string): string {
  if (/^https?:\/\//i.test(url) || url.startsWith("blob:") || url.startsWith("data:")) return url;
  return url;
}

/** 32px LQIP for first-paint backdrop only. Never the only gallery card image. */
export function cheapCoverUrl(model: CoverFields): string | null {
  return model.cover_lqip_url || model.cover_url || null;
}

/** Sharp cover for model detail / review. Falls back to LQIP if that is all that is ready. */
export function fullCoverUrl(model: CoverFields): string | null {
  return model.cover_url || model.cover_lqip_url || null;
}
