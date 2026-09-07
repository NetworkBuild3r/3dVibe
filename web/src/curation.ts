import type { CurationPollStatus, CurationProposal } from "./types";
import { formatRelativeTime } from "./format";

export const FILTERS = [
  { id: "pending", label: "Pending" },
  { id: "approved", label: "Approved" },
  { id: "rejected", label: "Rejected" },
  { id: "all", label: "All" }
] as const;

export type CurationFilter = (typeof FILTERS)[number]["id"];

export type ApplyPhase = "pending" | "rejected" | "applying" | "applied" | "failed";

export type StatusTone = "slate" | "accent" | "rose" | "amber";

export type StatusPill = {
  key: string;
  label: string;
  tone: StatusTone;
};

function firstText(...values: unknown[]) {
  for (const value of values) {
    if (typeof value === "string" && value.trim()) return value.trim();
  }
  return null;
}

function payloadOf(proposal: Pick<CurationProposal, "payload">) {
  return proposal.payload || {};
}

export function proposalRationale(proposal: CurationProposal) {
  const payload = payloadOf(proposal);
  return firstText(
    proposal.rationale,
    proposal.reason,
    proposal.explanation,
    payload.rationale,
    payload.reason,
    payload.explanation
  );
}

export function proposalConfidence(proposal: CurationProposal) {
  const payload = payloadOf(proposal);
  const value = proposal.confidence ?? payload.confidence;
  if (value == null || value === "") return null;
  if (typeof value === "number" && Number.isFinite(value)) {
    if (value >= 0 && value <= 1) return `${Math.round(value * 100)}%`;
    return String(value);
  }
  const text = String(value).trim();
  if (!text) return null;
  if (/^(0|1|0?\.\d+)$/.test(text)) {
    const numeric = Number(text);
    if (Number.isFinite(numeric) && numeric >= 0 && numeric <= 1) return `${Math.round(numeric * 100)}%`;
  }
  const lower = text.toLowerCase();
  if (lower === "low") return "Low";
  if (lower === "med" || lower === "medium") return "Med";
  if (lower === "high") return "High";
  return text;
}

export function applyPhase(proposal: Pick<CurationProposal, "status" | "applied_at" | "apply_error">): ApplyPhase {
  if (proposal.status === "pending") return "pending";
  if (proposal.status === "rejected") return "rejected";
  if (proposal.apply_error) return "failed";
  if (proposal.applied_at) return "applied";
  return "applying";
}

export function isApplying(proposal: Pick<CurationProposal, "status" | "applied_at" | "apply_error">) {
  return applyPhase(proposal) === "applying";
}

export function statusPills(proposal: CurationProposal): StatusPill[] {
  const phase = applyPhase(proposal);
  const pills: StatusPill[] = [];
  if (proposal.status === "pending") pills.push({ key: "status", label: "pending", tone: "slate" });
  else if (proposal.status === "approved") pills.push({ key: "status", label: "approved", tone: "accent" });
  else if (proposal.status === "rejected") pills.push({ key: "status", label: "rejected", tone: "rose" });
  else pills.push({ key: "status", label: proposal.status, tone: "slate" });

  if (phase === "applying") pills.push({ key: "apply", label: "Applying…", tone: "amber" });
  if (phase === "applied") pills.push({ key: "apply", label: "Applied", tone: "accent" });
  if (phase === "failed") pills.push({ key: "apply", label: "Apply failed", tone: "rose" });
  return pills;
}

export function appliedLabel(appliedAt?: string | null) {
  const when = formatRelativeTime(appliedAt) || (appliedAt ? new Date(appliedAt).toLocaleString() : null);
  return when ? `Applied ${when}` : "Applied";
}

export function lastRunLabel(lastPolledAt?: string | null) {
  if (!lastPolledAt) return "Never polled";
  const relative = formatRelativeTime(lastPolledAt);
  return relative ? `Last run ${relative}` : "Never polled";
}

export function pollFromUnknown(value: unknown): CurationPollStatus | null {
  if (!value || typeof value !== "object") return null;
  const row = value as Record<string, unknown>;
  return {
    last_polled_at: typeof row.last_polled_at === "string" ? row.last_polled_at : null,
    last_provider: typeof row.last_provider === "string" ? row.last_provider : null,
    last_error: typeof row.last_error === "string" ? row.last_error : null
  };
}

export function resolveCurationLibraryId<T extends { id: number }>(
  libraries: T[],
  selectedId: number | ""
): number | "" {
  if (typeof selectedId === "number" && libraries.some((library) => library.id === selectedId)) {
    return selectedId;
  }
  return libraries[0]?.id ?? "";
}

export function resolveCurationLibrary<T extends { id: number }>(
  libraries: T[],
  selectedId: number | ""
): T | undefined {
  const id = resolveCurationLibraryId(libraries, selectedId);
  if (id === "") return undefined;
  return libraries.find((library) => library.id === id);
}

export function curationFetchLibraryId<T extends { id: number }>(
  libraries: T[],
  selectedId: number | ""
): number | null {
  const id = resolveCurationLibraryId(libraries, selectedId);
  return id === "" ? null : id;
}

export function proposalsForLibrary<T extends { library_id: number }>(
  proposals: T[],
  libraryId: number | "" | null
): T[] {
  if (libraryId === "" || libraryId == null) return [];
  return proposals.filter((proposal) => proposal.library_id === libraryId);
}

export function pollForLibrary<T extends { id: number; curation?: CurationPollStatus }>(
  libraries: T[],
  libraryId: number | "" | null,
  fallback: Array<{ id: number; curation?: CurationPollStatus }> = []
): CurationPollStatus | undefined {
  if (libraryId === "" || libraryId == null) return undefined;
  return (
    libraries.find((library) => library.id === libraryId)?.curation ||
    fallback.find((library) => library.id === libraryId)?.curation
  );
}
