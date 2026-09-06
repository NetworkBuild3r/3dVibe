import type { CoverStatus, ModelCard } from "./api";

export type CoverVisual = "image" | "shimmer" | "placeholder";

export function coverStatusOf(model: Pick<ModelCard, "cover_status" | "cover_url" | "cover_placeholder">): CoverStatus {
  if (model.cover_status) return model.cover_status;
  if (model.cover_url && model.cover_placeholder === false) return "ready";
  if (model.cover_placeholder) return "missing";
  return "missing";
}

export function coverVisual(model: Pick<ModelCard, "cover_status" | "cover_url" | "cover_placeholder">): CoverVisual {
  const status = coverStatusOf(model);
  if (status === "ready" && model.cover_url) return "image";
  if (status === "pending") return "shimmer";
  return "placeholder";
}

export function hasReadyCover(model: Pick<ModelCard, "cover_status" | "cover_url" | "cover_placeholder">) {
  return coverVisual(model) === "image";
}

export function resolveCoverUrl(url: string): string {
  if (/^https?:\/\//i.test(url) || url.startsWith("blob:") || url.startsWith("data:")) return url;
  return url;
}
