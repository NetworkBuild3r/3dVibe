import { ApiError, type DuplicateAsset, type DuplicateConfidence, type DuplicateGroup, type DuplicateMember, type DuplicateReason, type DuplicateStatus, type ModelCard } from "./api";

export const MERGE_UNSUPPORTED = "merge_unsupported";
export const MERGE_UNSUPPORTED_COPY =
  "Merge needs on-disk models. Archive hits can be Kept or Dismissed — we don't extract packs this slice.";
export const GEOMETRY_ARCHIVE_LEGEND = "Geometry matches across loose files and meshes inside zip/7z/rar.";

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
  members: DuplicateMember[];
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

export function assetAsMember(asset: DuplicateAsset): DuplicateMember {
  return {
    kind: "asset",
    mergeable: asset.mergeable !== false,
    id: asset.id,
    asset_id: asset.id,
    filename: asset.filename,
    relative_path: asset.relative_path,
    byte_size: asset.byte_size,
    content_digest: asset.content_digest,
    geometry_digest: asset.geometry_digest,
    model_id: asset.model_id,
    model_title: asset.model_title,
    folder_name: asset.folder_name,
    cover_status: asset.cover_status,
    cover_url: asset.cover_url,
    cover_placeholder: asset.cover_placeholder
  };
}

export function groupMembers(group: DuplicateGroup): DuplicateMember[] {
  if (group.members && group.members.length > 0) return group.members;
  return (group.assets || []).map(assetAsMember);
}

export function isArchiveResident(member: Pick<DuplicateMember, "kind" | "archive_member_id" | "archive_path">) {
  return member.kind === "archive_member" || member.archive_member_id != null || Boolean(member.archive_path);
}

export function groupHasArchive(group: DuplicateGroup) {
  return groupMembers(group).some(isArchiveResident);
}

export function allMembersMergeable(group: DuplicateGroup) {
  const members = groupMembers(group);
  return members.length > 0 && members.every((member) => member.mergeable !== false);
}

export function memberKey(member: DuplicateMember) {
  if (isArchiveResident(member)) return `archive_member:${member.archive_member_id ?? member.id}`;
  return `asset:${member.asset_id ?? member.id}`;
}

export function archivePathOf(member: DuplicateMember) {
  if (member.archive_path) return member.archive_path;
  const pack = member.parent_filename;
  const inner = member.member_path;
  if (pack && inner) return `${pack} → ${inner}`;
  return inner || member.filename;
}

export function memberDisplayPath(member: DuplicateMember) {
  if (isArchiveResident(member)) return archivePathOf(member);
  return member.relative_path || member.filename;
}

export function truncateMiddle(value: string, max = 52) {
  const text = value ?? "";
  if (text.length <= max) return text;
  const inner = Math.max(2, max - 1);
  const head = Math.max(8, Math.ceil(inner * 0.55));
  const tail = Math.max(8, inner - head);
  if (head + tail >= text.length) return text;
  return `${text.slice(0, head)}…${text.slice(-tail)}`;
}

export function truncateArchivePath(value: string, max = 52) {
  if (value.length <= max) return value;
  const sep = " → ";
  const index = value.indexOf(sep);
  if (index === -1) return truncateMiddle(value, max);
  const pack = value.slice(0, index);
  const inner = value.slice(index + sep.length);
  const budget = max - pack.length - sep.length;
  if (budget < 10) return truncateMiddle(value, max);
  return `${pack}${sep}${truncateMiddle(inner, budget)}`;
}

export function isMergeUnsupported(err: unknown) {
  if (err instanceof ApiError && err.code === MERGE_UNSUPPORTED) return true;
  return err instanceof Error && (err.message === MERGE_UNSUPPORTED || /merge_unsupported/i.test(err.message));
}

export function memberColumns(group: DuplicateGroup): MemberColumn[] {
  const models = new Map((group.models || []).map((model) => [model.id, model]));
  const byModel = new Map<number, DuplicateMember[]>();
  groupMembers(group).forEach((member) => {
    const rows = byModel.get(member.model_id) || [];
    rows.push(member);
    byModel.set(member.model_id, rows);
  });
  return [...byModel.entries()].map(([modelId, members]) => {
    const model = models.get(modelId);
    return {
      modelId,
      model,
      title: model?.title || members[0]?.model_title || `Model ${modelId}`,
      members
    };
  });
}

export function coverFromMembers(
  members: DuplicateMember[],
  title: string
): Pick<ModelCard, "title" | "cover_status" | "cover_url" | "cover_placeholder"> | undefined {
  const member = members.find((item) => item.cover_status || item.cover_url || item.cover_placeholder != null);
  if (!member) return undefined;
  return {
    title,
    cover_status: member.cover_status,
    cover_url: member.cover_url,
    cover_placeholder: member.cover_placeholder
  };
}

export function previewModels(
  group: DuplicateGroup,
  limit = 4
): Array<ModelCard | Pick<ModelCard, "title" | "cover_status" | "cover_url" | "cover_placeholder"> | undefined> {
  const columns = memberColumns(group);
  const models = columns.map((column) => column.model || coverFromMembers(column.members, column.title));
  return models.slice(0, Math.min(Math.max(models.length, 2), limit));
}
