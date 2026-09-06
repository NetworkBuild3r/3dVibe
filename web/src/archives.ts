import { ApiError, type ArchiveMember, type ArchiveSummary, type Asset } from "./api";
import { truncateArchivePath, truncateMiddle } from "./duplicates";

export const CANCELLED_COPY = "Cancelled";
export const CANT_PREVIEW_COPY = "Can't preview this member";
export const ARCHIVE_STREAM_COPY = "One member at a time. The pack stays on disk.";

export type MemberKind = "mesh" | "image" | "other";
export type ArchiveView = "tree" | "flat";

export function memberKind(member: Pick<ArchiveMember, "mesh" | "image" | "directory">): MemberKind {
  if (member.mesh) return "mesh";
  if (member.image) return "image";
  return "other";
}

export function packFilename(assetId: number, archives: ArchiveSummary[], assets: Asset[] = []) {
  return (
    archives.find((item) => item.asset_id === assetId)?.filename ||
    assets.find((item) => item.id === assetId)?.filename ||
    "pack.zip"
  );
}

export function memberCaption(pack: string, path: string) {
  const inner = path.replace(/\/$/, "");
  return `${pack} → ${inner || pack}`;
}

export function captionForMember(
  member: Pick<ArchiveMember, "asset_id" | "internal_path">,
  archives: ArchiveSummary[],
  assets: Asset[] = []
) {
  return memberCaption(packFilename(member.asset_id, archives, assets), member.internal_path);
}

export function displayCaption(caption: string, max = 56) {
  return truncateArchivePath(caption, max);
}

export function folderSegments(prefix: string) {
  return prefix
    .split("/")
    .map((part) => part.trim())
    .filter(Boolean);
}

export function prefixThrough(segments: string[], index: number) {
  return `${segments.slice(0, index + 1).join("/")}/`;
}

export function isPreviewUnavailable(error: unknown) {
  if (!(error instanceof ApiError)) {
    return error instanceof Error && /oversized|not streamable|preview_unavailable|directory/i.test(error.message);
  }
  if (error.code === "preview_unavailable" || error.code === "use_content") return true;
  if (error.status === 422) return true;
  return /oversized|not streamable|directory/i.test(error.message);
}

export function viewerStatusCopy(error: unknown) {
  if (isPreviewUnavailable(error)) return CANT_PREVIEW_COPY;
  return error instanceof Error ? error.message : "Could not load file";
}

export function progressLabel(kind: "mesh" | "image", loaded: number, total: number | null) {
  if (total && total > 0) {
    const pct = Math.min(99, Math.round((loaded / total) * 100));
    return kind === "mesh" ? `Loading mesh… ${pct}%` : `Loading image… ${pct}%`;
  }
  return kind === "mesh" ? "Loading mesh…" : "Loading image…";
}

export { truncateArchivePath, truncateMiddle };
