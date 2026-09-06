import type {
  CoverBacklog,
  CurationPollStatus,
  GeometryBacklog,
  LibraryScanDetail,
  MeiliHealth,
  OpsSnapshot,
  ScanBudgets,
  ScanResume,
  ScanStatus
} from "./api";
import { formatRelativeTime } from "./format";

export const OPS_POLL_MS = 10_000;

export type OpsTone = "slate" | "accent" | "rose";

export type OpsChip = {
  key: string;
  label: string;
  tone: OpsTone;
  muted?: string;
  quiet?: boolean;
};

const ACTIVE_SCAN = new Set(["queued", "running", "budgeted"]);

function firstText(...values: unknown[]) {
  for (const value of values) {
    if (typeof value === "string" && value.trim()) return value.trim();
  }
  return null;
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" ? (value as Record<string, unknown>) : null;
}

function asNumber(value: unknown) {
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

function asString(value: unknown) {
  return typeof value === "string" && value.trim() ? value : null;
}

export function isActiveScan(scan?: ScanStatus | null) {
  return Boolean(scan?.status && ACTIVE_SCAN.has(scan.status));
}

export function scanPrefix(scan?: ScanStatus | null) {
  return firstText(scan?.path_prefix, scan?.resume?.path_prefix, scan?.resume?.resume_after);
}

export function scanChip(scan?: ScanStatus | null): OpsChip {
  if (isActiveScan(scan)) {
    const parts = ["Scanning"];
    if (scan?.phase) parts.push(scan.phase);
    const prefix = scanPrefix(scan);
    if (prefix) parts.push(prefix);
    return { key: "scan", label: parts.join(" · "), tone: "accent" };
  }
  if (!scan || scan.status === "idle") {
    return { key: "scan", label: "Never scanned", tone: "slate" };
  }
  const when = scan.finished_at || scan.started_at || scan.updated_at;
  const relative = formatRelativeTime(when);
  return {
    key: "scan",
    label: relative ? `Last scan · ${relative}` : "Never scanned",
    tone: scan.status === "failed" ? "rose" : "slate"
  };
}

export function curatorChip(curator?: CurationPollStatus | null): OpsChip {
  if (curator?.last_error) {
    return { key: "curator", label: curator.last_error, tone: "rose" };
  }
  const parts = ["Poll"];
  if (curator?.last_provider) parts.push(curator.last_provider);
  const relative = formatRelativeTime(curator?.last_polled_at);
  if (relative) parts.push(relative);
  else parts.push("never");
  return { key: "curator", label: parts.join(" · "), tone: "slate" };
}

export function coversChip(covers?: CoverBacklog | null): OpsChip | null {
  const pending = covers?.pending ?? 0;
  const failed = covers?.failed ?? 0;
  if (pending <= 0 && failed <= 0) return null;
  if (pending <= 0) {
    return { key: "covers", label: `Covers · ${failed} failed`, tone: "slate", quiet: true };
  }
  return {
    key: "covers",
    label: `Covers · ${pending} pending`,
    tone: "slate",
    muted: failed > 0 ? `${failed} failed` : undefined
  };
}

export function geometryChip(geometry?: GeometryBacklog | null): OpsChip | null {
  const backlog = (geometry?.assets_missing ?? 0) + (geometry?.archive_members_missing ?? 0);
  if (backlog <= 0) return null;
  return { key: "geometry", label: `Fingerprints · ${backlog}`, tone: "slate" };
}

export function searchChip(meili?: MeiliHealth | null): OpsChip {
  if (meili?.status === "down") {
    return { key: "search", label: "Search · down", tone: "rose" };
  }
  return { key: "search", label: "Search · ok", tone: "slate" };
}

export function opsChips(ops: OpsSnapshot): OpsChip[] {
  return [
    scanChip(ops.scan),
    curatorChip(ops.curator),
    coversChip(ops.covers),
    geometryChip(ops.geometry),
    searchChip(ops.meili)
  ].filter((chip): chip is OpsChip => Boolean(chip));
}

export function parseScanResume(value: unknown): ScanResume | null {
  const row = asRecord(value);
  if (!row) return null;
  const resume: ScanResume = {
    resume_after: asString(row.resume_after),
    path_prefix: asString(row.path_prefix),
    resume_relative_path: asString(row.resume_relative_path)
  };
  if (!resume.resume_after && !resume.path_prefix && !resume.resume_relative_path) return null;
  return resume;
}

export function parseScanBudgets(value: unknown): ScanBudgets | undefined {
  const row = asRecord(value);
  if (!row) return undefined;
  return {
    max_seconds: asNumber(row.max_seconds) || undefined,
    max_files: asNumber(row.max_files) || undefined,
    max_folders: asNumber(row.max_folders) || undefined
  };
}

export function parseScanStatus(value: unknown): ScanStatus | null {
  const row = asRecord(value);
  if (!row || typeof row.status !== "string") return null;
  return {
    id: typeof row.id === "number" ? row.id : undefined,
    status: row.status,
    trigger: asString(row.trigger) ?? undefined,
    phase: asString(row.phase) ?? undefined,
    path_prefix: asString(row.path_prefix),
    started_at: asString(row.started_at),
    finished_at: asString(row.finished_at),
    resume_after: asString(row.resume_after),
    folders_seen: typeof row.folders_seen === "number" ? row.folders_seen : undefined,
    folders_indexed: typeof row.folders_indexed === "number" ? row.folders_indexed : undefined,
    folders_skipped: typeof row.folders_skipped === "number" ? row.folders_skipped : undefined,
    files_seen: typeof row.files_seen === "number" ? row.files_seen : undefined,
    files_changed: typeof row.files_changed === "number" ? row.files_changed : undefined,
    pruned_count: typeof row.pruned_count === "number" ? row.pruned_count : undefined,
    error_count: typeof row.error_count === "number" ? row.error_count : undefined,
    deep_walks: typeof row.deep_walks === "number" ? row.deep_walks : undefined,
    budget_exhausted: typeof row.budget_exhausted === "boolean" ? row.budget_exhausted : undefined,
    last_error: asString(row.last_error),
    budgets: parseScanBudgets(row.budgets),
    resume: parseScanResume(row.resume),
    updated_at: asString(row.updated_at) ?? undefined
  };
}

export function parseCurator(value: unknown): CurationPollStatus {
  const row = asRecord(value);
  return {
    last_polled_at: asString(row?.last_polled_at),
    last_provider: asString(row?.last_provider),
    last_error: asString(row?.last_error)
  };
}

export function parseMeili(value: unknown): MeiliHealth {
  const row = asRecord(value);
  const status = asString(row?.status) || "unset";
  return {
    status,
    configured: typeof row?.configured === "boolean" ? row.configured : undefined,
    last_error: asString(row?.last_error)
  };
}

export function parseOpsSnapshot(value: unknown): OpsSnapshot | null {
  const row = asRecord(value);
  if (!row || typeof row.library_id !== "number") return null;
  const scan = parseScanStatus(row.scan) || { status: "idle" };
  const covers = asRecord(row.covers);
  const geometry = asRecord(row.geometry);
  return {
    library_id: row.library_id,
    library_name: asString(row.library_name) || "Library",
    scan,
    curator: parseCurator(row.curator),
    covers: {
      pending: asNumber(covers?.pending),
      failed: asNumber(covers?.failed),
      missing: asNumber(covers?.missing)
    },
    geometry: {
      assets_missing: asNumber(geometry?.assets_missing),
      archive_members_missing: asNumber(geometry?.archive_members_missing)
    },
    meili: parseMeili(row.meili)
  };
}

export function parseOpsPayload(payload: {
  meili?: MeiliHealth;
  libraries?: unknown[];
  ops?: unknown;
}): OpsSnapshot | null {
  const fromOps = parseOpsSnapshot(payload.ops);
  if (fromOps) {
    return payload.meili ? { ...fromOps, meili: parseMeili(payload.meili) } : fromOps;
  }
  const first = payload.libraries?.map(parseOpsSnapshot).find(Boolean) || null;
  if (!first) return null;
  return payload.meili ? { ...first, meili: parseMeili(payload.meili) } : first;
}

export function parseLibraryScan(value: unknown): LibraryScanDetail | null {
  const row = asRecord(value);
  if (!row || typeof row.library_id !== "number") return null;
  const scan = parseScanStatus(row.scan);
  if (!scan) return null;
  return {
    library_id: row.library_id,
    scan,
    current: parseScanStatus(row.current),
    last: parseScanStatus(row.last)
  };
}

export function scanWhen(scan?: ScanStatus | null) {
  return formatRelativeTime(scan?.finished_at || scan?.started_at || scan?.updated_at);
}
