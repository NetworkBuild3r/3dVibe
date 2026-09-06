import { ApiError } from "./api";
import { CANT_PREVIEW_COPY, CANCELLED_COPY, progressLabel } from "./archives";

/** Viewable mesh kinds — gcode/bgcode are `asset.mesh` but not a 3D preview. */
export const VIEWABLE_MESH_KINDS = ["stl", "obj", "3mf"] as const;
export type MeshFormat = (typeof VIEWABLE_MESH_KINDS)[number];

export type MeshSource = "loose" | "archive";

/**
 * Frontend shell stages for the lazy 3D viewer.
 * Keep these stable — ModelPage / MeshViewer / ImageViewer bind copy to them.
 */
export const VIEWER_STAGES = [
  "idle",
  "fetching",
  "decoding",
  "displaying",
  "ready",
  "cancelled",
  "unavailable"
] as const;
export type ViewerStage = (typeof VIEWER_STAGES)[number];

export const VIEWER_LOOSE_MAX_BYTES = 64 * 1024 * 1024;
export const VIEWER_ARCHIVE_MAX_BYTES = 32 * 1024 * 1024;
export const VIEWER_MAX_VERTS = 1_500_000;

export const DECODING_COPY = "Decoding mesh…";
export const DISPLAYING_COPY = "Loading remaining…";

export type MeshViewerErrorCode = "oversized" | "too_many_verts" | "unsupported" | "empty" | "cancelled";

export class MeshViewerError extends Error {
  readonly code: MeshViewerErrorCode;

  constructor(code: MeshViewerErrorCode, message = CANT_PREVIEW_COPY) {
    super(message);
    this.name = "MeshViewerError";
    this.code = code;
  }
}

export function isViewableMeshKind(kind?: string | null): kind is MeshFormat {
  return VIEWABLE_MESH_KINDS.includes(normalizeExt(kind) as MeshFormat);
}

export function isViewableMeshAsset(asset: { kind?: string | null; mesh?: boolean }) {
  return isViewableMeshKind(asset.kind);
}

export function normalizeExt(value?: string | null) {
  return (value || "").trim().toLowerCase().replace(/^\./, "");
}

export function meshFormatFromName(name?: string | null): MeshFormat | null {
  if (!name) return null;
  const cleaned = name.split("?")[0].split("#")[0];
  const slash = cleaned.lastIndexOf("/");
  const base = slash >= 0 ? cleaned.slice(slash + 1) : cleaned;
  const dot = base.lastIndexOf(".");
  if (dot < 0) return null;
  const ext = normalizeExt(base.slice(dot + 1));
  return isViewableMeshKind(ext) ? ext : null;
}

export function meshFormatFromHints(hints: {
  kind?: string | null;
  filename?: string | null;
  label?: string | null;
  url?: string | null;
}): MeshFormat | null {
  const kind = normalizeExt(hints.kind);
  if (isViewableMeshKind(kind)) return kind;
  return meshFormatFromName(hints.filename) || meshFormatFromName(hints.label) || meshFormatFromName(hints.url);
}

export function inferMeshSource(url?: string | null): MeshSource {
  return url && /\/archive_members\//i.test(url) ? "archive" : "loose";
}

export function defaultViewerMaxBytes(source: MeshSource) {
  return source === "archive" ? VIEWER_ARCHIVE_MAX_BYTES : VIEWER_LOOSE_MAX_BYTES;
}

export function resolveViewerMaxBytes(options: { source?: MeshSource | null; url?: string | null; maxBytes?: number | null }) {
  if (options.maxBytes != null && options.maxBytes > 0) return options.maxBytes;
  return defaultViewerMaxBytes(options.source || inferMeshSource(options.url));
}

export function isOversize(bytes: number, maxBytes: number) {
  return maxBytes > 0 && bytes > maxBytes;
}

export function isOverVertBudget(verts: number, maxVerts: number) {
  return maxVerts > 0 && verts > maxVerts;
}

export function throwIfOversize(bytes: number, maxBytes: number) {
  if (isOversize(bytes, maxBytes)) throw new MeshViewerError("oversized");
}

export function throwIfOverVerts(verts: number, maxVerts: number) {
  if (isOverVertBudget(verts, maxVerts)) throw new MeshViewerError("too_many_verts");
}

export function viewerStageCopy(
  stage: ViewerStage,
  options: { label?: string; loaded?: number; total?: number | null } = {}
) {
  switch (stage) {
    case "fetching":
      return progressLabel("mesh", options.loaded ?? 0, options.total ?? null);
    case "decoding":
      return DECODING_COPY;
    case "displaying":
      return DISPLAYING_COPY;
    case "ready":
      return options.label || "Mesh";
    case "cancelled":
      return CANCELLED_COPY;
    case "unavailable":
      return CANT_PREVIEW_COPY;
    default:
      return "Load a mesh to preview.";
  }
}

export function isMeshBudgetError(error: unknown) {
  if (error instanceof MeshViewerError) {
    return error.code === "oversized" || error.code === "too_many_verts" || error.code === "unsupported" || error.code === "empty";
  }
  if (error instanceof ApiError) {
    return error.code === "oversized" || error.code === "too_many_verts" || error.code === "unsupported" || error.code === "empty";
  }
  return error instanceof Error && /oversized|too_many_verts|unsupported|empty mesh/i.test(error.message);
}

export function meshViewerStatusCopy(error: unknown) {
  if (error instanceof MeshViewerError && error.code === "cancelled") return CANCELLED_COPY;
  if (isMeshBudgetError(error)) return CANT_PREVIEW_COPY;
  if (error instanceof ApiError && (error.status === 422 || error.code === "preview_unavailable" || error.code === "use_content")) {
    return CANT_PREVIEW_COPY;
  }
  return error instanceof Error ? error.message : "Could not load file";
}

/** Preferred loose mesh for the Load mesh CTA — skip archives until the user opens a member. */
export function preferredLooseMesh<T extends { mesh?: boolean; kind?: string | null; archive?: boolean }>(assets: T[]) {
  return assets.find((asset) => isViewableMeshAsset(asset) && !asset.archive) || assets.find((asset) => isViewableMeshAsset(asset));
}
