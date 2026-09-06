import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { Link } from "react-router-dom";
import { ApiError, api, type LibraryScanDetail, type OpsSnapshot, type ScanStatus } from "../api";
import { useAuth } from "../auth";
import { formatRelativeTime } from "../format";
import {
  OPS_POLL_MS,
  isActiveScan,
  opsChips,
  parseLibraryScan,
  parseOpsPayload,
  scanPrefix,
  type OpsChip,
  type OpsTone
} from "../ops";
import { Pulse } from "./UiStates";

const toneClass: Record<OpsTone, string> = {
  slate: "border-white/10 text-slate-300 hover:border-white/20 hover:text-white",
  accent: "border-accent-500/40 text-accent-300 hover:border-accent-500/60",
  rose: "border-rose-400/30 text-rose-300 hover:border-rose-400/50"
};

function OpsChipButton({
  chip,
  expanded,
  onClick
}: {
  chip: OpsChip;
  expanded: boolean;
  onClick: () => void;
}) {
  const showMutedExtra = chip.key === "covers" && chip.muted && !chip.label.endsWith(chip.muted);
  return (
    <button
      type="button"
      aria-expanded={expanded}
      aria-controls="library-ops-detail"
      onClick={onClick}
      className={`inline-flex items-center gap-1.5 rounded-full border px-3 py-1.5 text-sm transition ${toneClass[chip.tone]} ${
        chip.quiet ? "text-slate-500 hover:text-slate-400" : ""
      } ${expanded ? "bg-white/5" : "bg-transparent"}`}
    >
      <span>{chip.label}</span>
      {showMutedExtra ? <span className="text-slate-500">· {chip.muted}</span> : null}
    </button>
  );
}

function DetailRow({ label, children }: { label: string; children: ReactNode }) {
  if (children == null || children === "") return null;
  return (
    <div>
      <dt className="text-[11px] uppercase tracking-wide text-slate-500">{label}</dt>
      <dd className="mt-0.5 text-slate-200">{children}</dd>
    </div>
  );
}

function formatScanLine(scan?: ScanStatus | null) {
  if (!scan) return null;
  const bits = [scan.status];
  if (scan.phase) bits.push(scan.phase);
  const prefix = scanPrefix(scan);
  if (prefix) bits.push(prefix);
  const when = formatRelativeTime(scan.finished_at || scan.started_at);
  if (when) bits.push(when);
  return bits.join(" · ");
}

function budgetsLine(scan?: ScanStatus | null) {
  const budgets = scan?.budgets;
  if (!budgets) return null;
  const parts = [];
  if (budgets.max_seconds != null) parts.push(`${budgets.max_seconds}s`);
  if (budgets.max_files != null) parts.push(`${budgets.max_files} files`);
  if (budgets.max_folders != null) parts.push(`${budgets.max_folders} folders`);
  return parts.length ? parts.join(" · ") : null;
}

function resumeLine(scan?: ScanStatus | null) {
  const resume = scan?.resume;
  if (!resume) return scan?.resume_after || null;
  return [resume.resume_after || resume.path_prefix, resume.resume_relative_path].filter(Boolean).join(" / ") || null;
}

function OpsDetail({
  ops,
  scanDetail,
  canOpenLibraries
}: {
  ops: OpsSnapshot;
  scanDetail: LibraryScanDetail | null;
  canOpenLibraries: boolean;
}) {
  const scan = scanDetail?.scan || ops.scan;
  const current = scanDetail?.current;
  const last = scanDetail?.last;
  const active = isActiveScan(current || scan);

  return (
    <div
      id="library-ops-detail"
      className="mt-3 rounded-2xl border border-white/10 bg-ink-900/70 px-4 py-3 text-sm"
    >
      <p className="text-xs text-slate-500">
        Index health for {ops.library_name}. NFS stays the source of truth.
      </p>
      <dl className="mt-3 grid gap-3 sm:grid-cols-2">
        <DetailRow label="Scan">{formatScanLine(scan)}</DetailRow>
        <DetailRow label={active ? "Current" : "Last"}>
          {active ? formatScanLine(current || scan) : formatScanLine(last || scan)}
        </DetailRow>
        <DetailRow label="Phase">{scan.phase || (scan.status === "idle" ? "—" : null)}</DetailRow>
        <DetailRow label="Prefix">{scanPrefix(scan)}</DetailRow>
        <DetailRow label="Budgets">{budgetsLine(scan)}</DetailRow>
        <DetailRow label="Resume">{resumeLine(scan)}</DetailRow>
        <DetailRow label="Scan errors">
          {scan.error_count || scan.last_error ? (
            <span className={scan.last_error ? "text-rose-300" : undefined}>
              {scan.error_count ? `${scan.error_count} ` : ""}
              {scan.last_error || "errors"}
            </span>
          ) : (
            "none"
          )}
        </DetailRow>
        <DetailRow label="Curator">
          {ops.curator.last_error ? (
            <span className="text-rose-300">{ops.curator.last_error}</span>
          ) : (
            [ops.curator.last_provider || "—", formatRelativeTime(ops.curator.last_polled_at) || "never"]
              .filter(Boolean)
              .join(" · ")
          )}
        </DetailRow>
        <DetailRow label="Covers">
          {`${ops.covers.pending} pending · ${ops.covers.failed} failed · ${ops.covers.missing} missing`}
        </DetailRow>
        <DetailRow label="Fingerprints">
          {`${ops.geometry.assets_missing + ops.geometry.archive_members_missing} backlog · ${ops.geometry.assets_missing} assets · ${ops.geometry.archive_members_missing} members`}
        </DetailRow>
        <DetailRow label="Search">
          {ops.meili.status === "down" ? (
            <span className="text-rose-300">{ops.meili.last_error || "down"}</span>
          ) : (
            ops.meili.status === "unset" ? "ok · Postgres fallback" : "ok"
          )}
        </DetailRow>
      </dl>
      {canOpenLibraries ? (
        <p className="mt-3 text-xs text-slate-500">
          <Link to="/libraries" className="text-accent-400 hover:text-accent-300">
            Libraries
          </Link>
        </p>
      ) : null}
    </div>
  );
}

export function OpsStrip() {
  const { user } = useAuth();
  const canReadOps = Boolean(user?.can_curate);
  const canOpenLibraries = Boolean(user?.can_invite || user?.can_manage_libraries);
  const [ops, setOps] = useState<OpsSnapshot | null>(null);
  const [scanDetail, setScanDetail] = useState<LibraryScanDetail | null>(null);
  const [loading, setLoading] = useState(canReadOps);
  const [error, setError] = useState(false);
  const [hidden, setHidden] = useState(!canReadOps);
  const [expanded, setExpanded] = useState(false);
  const mounted = useRef(true);
  const expandedRef = useRef(false);

  useEffect(() => {
    mounted.current = true;
    return () => {
      mounted.current = false;
    };
  }, []);

  useEffect(() => {
    expandedRef.current = expanded;
  }, [expanded]);

  const load = useCallback(async (options: { silent?: boolean } = {}) => {
    if (!canReadOps) return;
    if (!options.silent) {
      setLoading(true);
      setError(false);
    }
    try {
      const payload = await api.ops();
      if (!mounted.current) return;
      const next = parseOpsPayload(payload);
      if (!next) {
        setHidden(true);
        setOps(null);
        setLoading(false);
        return;
      }
      setOps(next);
      setHidden(false);
      setError(false);
      if (expandedRef.current) {
        try {
          const detail = parseLibraryScan(await api.libraryScan(next.library_id));
          if (mounted.current) setScanDetail(detail);
        } catch {
          if (mounted.current) setScanDetail(null);
        }
      }
    } catch (err) {
      if (!mounted.current) return;
      if (err instanceof ApiError && err.status === 403) {
        setHidden(true);
        setOps(null);
        setError(false);
        return;
      }
      setError(true);
    } finally {
      if (mounted.current) setLoading(false);
    }
  }, [canReadOps]);

  useEffect(() => {
    if (!canReadOps) {
      setHidden(true);
      setLoading(false);
      return;
    }
    void load();

    function onVisibility() {
      if (document.visibilityState === "visible") void load({ silent: true });
    }
    document.addEventListener("visibilitychange", onVisibility);
    const timer = window.setInterval(() => {
      if (document.visibilityState === "visible") void load({ silent: true });
    }, OPS_POLL_MS);
    return () => {
      document.removeEventListener("visibilitychange", onVisibility);
      window.clearInterval(timer);
    };
  }, [canReadOps, load]);

  async function toggleExpand() {
    const next = !expanded;
    setExpanded(next);
    expandedRef.current = next;
    if (next && ops) {
      try {
        const detail = parseLibraryScan(await api.libraryScan(ops.library_id));
        if (mounted.current) setScanDetail(detail);
      } catch {
        if (mounted.current) setScanDetail(null);
      }
    }
  }

  const chips = useMemo(() => (ops ? opsChips(ops) : []), [ops]);

  if (hidden && !loading && !error) return null;

  if (loading && !ops) {
    return (
      <div className="flex flex-wrap gap-2" aria-hidden>
        <Pulse className="h-8 w-28 rounded-full" />
        <Pulse className="h-8 w-32 rounded-full" />
        <Pulse className="h-8 w-24 rounded-full" />
        <Pulse className="h-8 w-20 rounded-full" />
      </div>
    );
  }

  if (error && !ops) {
    return (
      <div className="flex flex-wrap items-center gap-3 text-sm text-slate-500">
        <p>Ops unavailable</p>
        <button type="button" className="text-accent-400 hover:text-accent-300" onClick={() => void load()}>
          Retry
        </button>
      </div>
    );
  }

  if (!ops) return null;

  return (
    <div aria-label="Library ops">
      <div className="flex flex-wrap items-center gap-2">
        {chips.map((chip) => (
          <OpsChipButton key={chip.key} chip={chip} expanded={expanded} onClick={() => void toggleExpand()} />
        ))}
      </div>
      {expanded ? <OpsDetail ops={ops} scanDetail={scanDetail} canOpenLibraries={canOpenLibraries} /> : null}
    </div>
  );
}
