import type { DuplicateAsset, DuplicateConfidence, DuplicateGroup, DuplicateReason, DuplicateStatus, ModelCard } from "./api";

export const STATUS_FILTERS = [
  { id: "open", label: "Open" },
  { id: "kept", label: "Kept" },
  { id: "dismissed", label: "Dismissed" },
  { id: "merged", label: "Merged" },
  { id: "all", label: "All" }
] as const;

export type StatusFilter = (typeof STATUS_FILTERS)[number]["id"];

export const CONFIDENCE_COPY: Record<
  DuplicateConfidence,
  { label: string; hint: string }
> = {
  exact: { label: "Exact", hint: "Same bytes" },
  geometry: { label: "Geometry", hint: "Same mesh, different files" },
  likely: { label: "Likely", hint: "Weak signal — human decides" }
};

export const REASON_COPY: Record<DuplicateReason, string> = {
  content_hash: "content hash",
  geometry: "geometry digest",
  name_size: "name and size"
};

export const STATUS_COPY: Record<DuplicateStatus, { label: string; hint: string }> = {
  open: { label: "Open", hint: "Waiting for a human decision" },
  kept: { label: "Kept", hint: "Intentional copies, still in the shared catalog" },
  dismissed: { label: "Dismissed", hint: "Not a duplicate — reversible from this filter, not a delete" },
  merged: { label: "Merged", hint: "Reparented through the path jail; files stay on disk" }
};

export type MemberColumn = {
  modelId: number;
  model?: ModelCard;
  title: string;
  assets: DuplicateAsset[];
};

export function confidenceOf(value: string): DuplicateConfidence {
  if (value === "exact" || value === "geometry" || value === "likely") return value;
  return "likely";
}

export function reasonOf(value: string): DuplicateReason {
  if (value === "content_hash" || value === "geometry" || value === "name_size") return value;
  return "name_size";
}

export function statusOf(value: string): DuplicateStatus {
  if (value === "open" || value === "kept" || value === "dismissed" || value === "merged") return value;
  return "open";
}

export function confidenceMeta(value: string) {
  const confidence = confidenceOf(value);
  return { confidence, ...CONFIDENCE_COPY[confidence] };
}

export function reasonLabel(value: string) {
  return REASON_COPY[reasonOf(value)];
}

export function statusMeta(value: string) {
  const status = statusOf(value);
  return { status, ...STATUS_COPY[status] };
}

export function digestSnippet(value?: string | null) {
  if (!value) return "—";
  if (value.length <= 16) return value;
  return `${value.slice(0, 8)}…${value.slice(-4)}`;
}

export function lastRunKey(libraryId: number) {
  return `vibe_dup_last_analyze_${libraryId}`;
}

export function readLastRun(libraryId: number) {
  try {
    return sessionStorage.getItem(lastRunKey(libraryId));
  } catch {
    return null;
  }
}

export function writeLastRun(libraryId: number, iso: string) {
  try {
    sessionStorage.setItem(lastRunKey(libraryId), iso);
  } catch {
    /* ignore quota / private mode */
  }
}

export function newestGroupTime(groups: DuplicateGroup[]) {
  return groups.reduce<string | null>((latest, group) => {
    const stamp = group.updated_at || group.created_at;
    if (!stamp) return latest;
    if (!latest || stamp > latest) return stamp;
    return latest;
  }, null);
}

export function formatWhen(value?: string | null) {
  if (!value) return null;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return null;
  return date.toLocaleString();
}

export function memberColumns(group: DuplicateGroup): MemberColumn[] {
  const models = new Map((group.models || []).map((model) => [model.id, model]));
  const byModel = new Map<number, DuplicateAsset[]>();
  group.assets.forEach((asset) => {
    const rows = byModel.get(asset.model_id) || [];
    rows.push(asset);
    byModel.set(asset.model_id, rows);
  });
  return [...byModel.entries()].map(([modelId, assets]) => {
    const model = models.get(modelId);
    return {
      modelId,
      model,
      title: model?.title || assets[0]?.model_title || `Model ${modelId}`,
      assets
    };
  });
}

export function coverFromAssets(assets: DuplicateAsset[], title: string): Pick<ModelCard, "title" | "cover_status" | "cover_url" | "cover_placeholder"> | undefined {
  const asset = assets.find((item) => item.cover_status || item.cover_url || item.cover_placeholder != null);
  if (!asset) return undefined;
  return {
    title,
    cover_status: asset.cover_status,
    cover_url: asset.cover_url,
    cover_placeholder: asset.cover_placeholder
  };
}

export function previewModels(group: DuplicateGroup, limit = 4): Array<ModelCard | Pick<ModelCard, "title" | "cover_status" | "cover_url" | "cover_placeholder"> | undefined> {
  const columns = memberColumns(group);
  const models = columns.map((column) => column.model || coverFromAssets(column.assets, column.title));
  return models.slice(0, Math.min(Math.max(models.length, 2), limit));
}
