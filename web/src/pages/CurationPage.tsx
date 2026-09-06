import { useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { Link } from "react-router-dom";
import { ApiError, api, type CurationPollStatus, type CurationProposal, type LibraryInfo } from "../api";
import { useAuth } from "../auth";
import { CalmChip } from "../components/CalmChip";
import { EmptyState, InlineError, Pulse } from "../components/UiStates";
import {
  FILTERS,
  appliedLabel,
  applyPhase,
  isApplying,
  lastRunLabel,
  pollFromUnknown,
  proposalConfidence,
  proposalRationale,
  statusPills,
  type CurationFilter,
  type StatusTone
} from "../curation";

function chips(values?: string[]) {
  if (!values?.length) return <span className="text-slate-500">none</span>;
  return (
    <span className="flex flex-wrap gap-1">
      {values.map((value) => (
        <span key={value} className="rounded-full bg-white/5 px-2 py-0.5 text-xs text-slate-300">
          {value}
        </span>
      ))}
    </span>
  );
}

const toneClass: Record<StatusTone, string> = {
  slate: "border-white/10 text-slate-300",
  accent: "border-accent-500/40 text-accent-300",
  rose: "border-rose-400/30 text-rose-300",
  amber: "border-amber-400/30 text-amber-200"
};

function Pill({ label, tone }: { label: string; tone: StatusTone }) {
  return (
    <span className={`inline-flex rounded-full border px-2 py-0.5 text-[11px] uppercase tracking-wide ${toneClass[tone]}`}>
      {label}
    </span>
  );
}

function StatusStripChip({
  children,
  tone = "slate"
}: {
  children: ReactNode;
  tone?: "slate" | "rose";
}) {
  return (
    <span
      className={`inline-flex items-center rounded-full border px-3 py-1.5 text-sm ${
        tone === "rose" ? "border-rose-400/30 text-rose-300" : "border-white/10 text-slate-300"
      }`}
    >
      {children}
    </span>
  );
}

function Preview({ proposal }: { proposal: CurationProposal }) {
  const preview = proposal.preview;
  const before = preview?.before || {};
  const after = preview?.after || {};
  const targets = preview?.targets || [];

  return (
    <div className="mt-4 grid gap-3 md:grid-cols-2">
      <div className="rounded-xl border border-white/10 bg-ink-950/80 p-3">
        <p className="text-xs uppercase tracking-wide text-slate-500">Before</p>
        <p className="mt-1 text-sm text-white">{before.title || "—"}</p>
        <p className="font-mono text-xs text-slate-400">{before.folder_name || "—"}</p>
        <div className="mt-2">{chips(before.tags)}</div>
      </div>
      <div className="rounded-xl border border-accent-500/20 bg-accent-500/5 p-3">
        <p className="text-xs uppercase tracking-wide text-accent-400">After</p>
        <p className="mt-1 text-sm text-white">{after.title || "—"}</p>
        <p className="font-mono text-xs text-slate-400">
          {after.merge_from ? `${after.merge_from} → ` : ""}
          {after.folder_name || "—"}
        </p>
        <div className="mt-2">{chips(after.tags)}</div>
        {preview?.filesystem ? (
          <p className="mt-2 text-xs text-amber-300">Path-jailed filesystem change on approve</p>
        ) : null}
      </div>
      {targets.length ? (
        <div className="md:col-span-2 flex flex-wrap gap-2 text-xs">
          {targets.map((target) => (
            <Link
              key={target.id}
              to={`/models/${target.id}`}
              className="rounded-full border border-white/10 px-2 py-1 text-slate-300 hover:border-accent-500/40 hover:text-white"
            >
              {target.title}
              <span className="ml-1 text-slate-500">{target.folder_name}</span>
            </Link>
          ))}
        </div>
      ) : null}
    </div>
  );
}

function ProposalSkeleton() {
  return (
    <article className="rounded-2xl border border-white/10 bg-ink-900/70 p-4" aria-hidden>
      <div className="flex gap-2">
        <Pulse className="h-5 w-16 rounded-full" />
        <Pulse className="h-5 w-20 rounded-full" />
      </div>
      <Pulse className="mt-3 h-5 w-2/3" />
      <Pulse className="mt-2 h-4 w-1/2" />
      <div className="mt-4 grid gap-3 md:grid-cols-2">
        <Pulse className="h-24 w-full" />
        <Pulse className="h-24 w-full" />
      </div>
    </article>
  );
}

function mergeLibraryPoll(
  libraries: LibraryInfo[],
  pollRows?: Array<{ id: number; curation?: CurationPollStatus }>,
  patch?: { libraryId: number; curation: CurationPollStatus }
) {
  return libraries.map((library) => {
    const fromIndex = pollRows?.find((row) => row.id === library.id);
    if (fromIndex?.curation) return { ...library, curation: fromIndex.curation };
    if (patch && patch.libraryId === library.id) return { ...library, curation: patch.curation };
    return library;
  });
}

function isPollFailure(err: unknown) {
  return err instanceof ApiError && (err.code === "curator_unreachable" || err.status === 502);
}

export function CurationPage() {
  const { user } = useAuth();
  const canCurate = Boolean(user?.can_curate);
  const [proposals, setProposals] = useState<CurationProposal[]>([]);
  const [libraries, setLibraries] = useState<LibraryInfo[]>([]);
  const [filter, setFilter] = useState<CurationFilter>("pending");
  const [selected, setSelected] = useState<number[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [polling, setPolling] = useState(false);
  const [acting, setActing] = useState(false);
  const mounted = useRef(true);
  const applyTicket = useRef(0);

  const visible = useMemo(
    () => (filter === "all" ? proposals : proposals.filter((proposal) => proposal.status === filter)),
    [filter, proposals]
  );
  const pendingOnFilter = filter === "pending";
  const pendingIds = pendingOnFilter
    ? visible.filter((proposal) => proposal.status === "pending").map((proposal) => proposal.id)
    : [];
  const activeLibrary = libraries[0];
  const poll = activeLibrary?.curation || user?.libraries?.[0]?.curation;
  const emptyCopy =
    filter === "pending"
      ? "No pending suggestions. Refresh after the sidecar is live — stub still works for CI."
      : "Nothing in this filter.";

  useEffect(() => {
    mounted.current = true;
    return () => {
      mounted.current = false;
    };
  }, []);

  async function refresh(options: { silent?: boolean } = {}) {
    if (!options.silent) {
      setError(null);
      setLoading(true);
    }
    try {
      const [proposalPayload, libraryPayload] = await Promise.all([api.proposals(), api.libraries()]);
      if (!mounted.current) return proposalPayload.proposals;
      setProposals(proposalPayload.proposals);
      setLibraries(mergeLibraryPoll(libraryPayload.libraries, proposalPayload.libraries));
      setSelected((current) =>
        current.filter((id) => proposalPayload.proposals.some((item) => item.id === id && item.status === "pending"))
      );
      if (!options.silent) setError(null);
      return proposalPayload.proposals;
    } catch (err) {
      if (mounted.current && !options.silent) {
        setError(err instanceof Error ? err.message : "Failed");
      }
      return null;
    } finally {
      if (mounted.current && !options.silent) setLoading(false);
    }
  }

  useEffect(() => {
    void refresh();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function waitForApply(ids: number[]) {
    const ticket = ++applyTicket.current;
    const started = Date.now();
    while (Date.now() - started < 12000 && applyTicket.current === ticket && mounted.current) {
      await new Promise((resolve) => window.setTimeout(resolve, 800));
      if (applyTicket.current !== ticket || !mounted.current) return;
      const next = await refresh({ silent: true });
      if (!next) continue;
      const stillApplying = next.some((proposal) => ids.includes(proposal.id) && isApplying(proposal));
      if (!stillApplying) break;
    }
  }

  async function act(id: number, action: "approve" | "reject") {
    if (!canCurate || acting) return;
    setActing(true);
    setError(null);
    try {
      const payload = action === "approve" ? await api.approveProposal(id) : await api.rejectProposal(id);
      await refresh({ silent: true });
      if (action === "approve" && isApplying(payload.proposal)) await waitForApply([id]);
    } catch (err) {
      if (mounted.current) setError(err instanceof Error ? err.message : "Action failed");
    } finally {
      if (mounted.current) setActing(false);
    }
  }

  async function bulk(action: "approve" | "reject") {
    if (!canCurate || acting || !selected.length || !pendingOnFilter) return;
    const ids = [...selected];
    setActing(true);
    setError(null);
    try {
      const payload = await api.bulkProposals(ids, action);
      setSelected([]);
      await refresh({ silent: true });
      if (action === "approve") {
        const applying = payload.proposals.filter(isApplying).map((proposal) => proposal.id);
        if (applying.length) await waitForApply(applying);
      }
    } catch (err) {
      if (mounted.current) setError(err instanceof Error ? err.message : "Bulk action failed");
    } finally {
      if (mounted.current) setActing(false);
    }
  }

  async function fetchFromSidecar() {
    if (!canCurate || polling) return;
    const libraryId = activeLibrary?.id;
    if (!libraryId) {
      setError("No library to curate");
      return;
    }
    setPolling(true);
    setError(null);
    try {
      const payload = await api.fetchProposals(libraryId);
      if (payload.curation && mounted.current) {
        setLibraries((current) => mergeLibraryPoll(current, undefined, { libraryId, curation: payload.curation! }));
      }
      await refresh({ silent: true });
    } catch (err) {
      const failedPoll = pollFromUnknown(err instanceof ApiError ? err.data.curation : null);
      if (failedPoll && mounted.current) {
        setLibraries((current) => mergeLibraryPoll(current, undefined, { libraryId, curation: failedPoll }));
      }
      await refresh({ silent: true });
      if (mounted.current && !isPollFailure(err)) {
        setError(err instanceof Error ? err.message : "Could not refresh proposals");
      }
    } finally {
      if (mounted.current) setPolling(false);
    }
  }

  function toggle(id: number) {
    setSelected((current) => (current.includes(id) ? current.filter((item) => item !== id) : [...current, id]));
  }

  function toggleAll() {
    setSelected((current) => (current.length === pendingIds.length ? [] : pendingIds));
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 className="font-display text-3xl text-white">Curation</h1>
          <p className="mt-2 max-w-2xl text-sm text-slate-400">
            Sidecar suggestions. Nothing changes on NFS until you approve.
          </p>
          <div className="mt-3 flex flex-wrap gap-2">
            <StatusStripChip>Provider {poll?.last_provider || "—"}</StatusStripChip>
            <StatusStripChip>{lastRunLabel(poll?.last_polled_at)}</StatusStripChip>
            {poll?.last_error ? <StatusStripChip tone="rose">{poll.last_error}</StatusStripChip> : null}
            {user?.can_invite ? (
              <Link
                to="/settings/curator"
                className="inline-flex items-center rounded-full border border-accent-500/30 px-3 py-1.5 text-sm text-accent-300 hover:border-accent-500/50 hover:text-accent-200"
              >
                Configure
              </Link>
            ) : null}
          </div>
        </div>
        {canCurate ? (
          <button
            type="button"
            disabled={polling || !activeLibrary}
            onClick={() => void fetchFromSidecar()}
            className="rounded-lg bg-accent-500 px-3 py-1.5 text-sm text-ink-950 disabled:opacity-60"
          >
            {polling ? "Polling…" : "Refresh proposals"}
          </button>
        ) : null}
      </div>

      <div className="flex flex-wrap items-center gap-2">
        {FILTERS.map((item) => (
          <CalmChip key={item.id} active={filter === item.id} onClick={() => setFilter(item.id)}>
            {item.label}
          </CalmChip>
        ))}
        {canCurate && pendingOnFilter && pendingIds.length ? (
          <>
            <button type="button" className="ml-2 text-sm text-slate-400 hover:text-white" onClick={toggleAll}>
              {selected.length === pendingIds.length ? "Clear" : "Select pending"}
            </button>
            <button
              type="button"
              disabled={acting || !selected.length}
              onClick={() => void bulk("approve")}
              className="rounded-lg bg-accent-500 px-3 py-1 text-sm text-ink-950 disabled:opacity-50"
            >
              Approve selected
            </button>
            <button
              type="button"
              disabled={acting || !selected.length}
              onClick={() => void bulk("reject")}
              className="rounded-lg border border-white/15 px-3 py-1 text-sm disabled:opacity-50"
            >
              Reject selected
            </button>
          </>
        ) : null}
      </div>

      {error ? <InlineError message={error} onRetry={() => void refresh()} /> : null}

      <section aria-busy={loading || polling}>
        <div className="space-y-3">
          {loading ? (
            <>
              <ProposalSkeleton />
              <ProposalSkeleton />
              <ProposalSkeleton />
            </>
          ) : (
            visible.map((proposal) => {
              const phase = applyPhase(proposal);
              const rationale = proposalRationale(proposal);
              const confidence = proposalConfidence(proposal);
              const showSelect = canCurate && pendingOnFilter && proposal.status === "pending";
              return (
                <article key={proposal.id} className="rounded-2xl border border-white/10 bg-ink-900/70 p-4">
                  <div className="flex flex-wrap items-start justify-between gap-3">
                    <div className="min-w-0 flex-1">
                      <div className="flex flex-wrap items-center gap-2">
                        {showSelect ? (
                          <input
                            type="checkbox"
                            className="mt-0.5"
                            checked={selected.includes(proposal.id)}
                            onChange={() => toggle(proposal.id)}
                            aria-label={`Select ${proposal.summary}`}
                          />
                        ) : null}
                        <Pill label={proposal.kind} tone="slate" />
                        {statusPills(proposal).map((pill) => (
                          <Pill key={pill.key} label={pill.label} tone={pill.tone} />
                        ))}
                        {confidence ? (
                          <span className="inline-flex rounded-full border border-white/10 px-2 py-0.5 text-[11px] uppercase tracking-wide text-slate-300">
                            {confidence}
                          </span>
                        ) : null}
                      </div>
                      <h2 className="mt-2 text-lg text-white">{proposal.summary}</h2>
                      {rationale ? <p className="mt-1 text-sm text-slate-400">{rationale}</p> : null}
                      <Preview proposal={proposal} />
                      {phase === "failed" && proposal.apply_error ? (
                        <p className="mt-2 text-sm text-rose-300">Apply failed: {proposal.apply_error}</p>
                      ) : null}
                      {proposal.sidecar_ref ? (
                        <p className="mt-3 font-mono text-[11px] text-slate-500">{proposal.sidecar_ref}</p>
                      ) : null}
                    </div>
                    {canCurate && phase === "pending" ? (
                      <div className="flex gap-2">
                        <button
                          type="button"
                          disabled={acting}
                          onClick={() => void act(proposal.id, "approve")}
                          className="rounded-lg bg-accent-500 px-3 py-1.5 text-sm text-ink-950 disabled:opacity-60"
                        >
                          Approve
                        </button>
                        <button
                          type="button"
                          disabled={acting}
                          onClick={() => void act(proposal.id, "reject")}
                          className="rounded-lg border border-white/15 px-3 py-1.5 text-sm disabled:opacity-60"
                        >
                          Reject
                        </button>
                      </div>
                    ) : canCurate && phase === "applying" ? (
                      <p className="text-sm text-amber-200">Applying…</p>
                    ) : canCurate && phase === "applied" ? (
                      <p className="text-sm text-slate-400">{appliedLabel(proposal.applied_at)}</p>
                    ) : null}
                  </div>
                </article>
              );
            })
          )}
        </div>
        {!loading && !error && visible.length === 0 ? <EmptyState copy={emptyCopy} /> : null}
      </section>
    </div>
  );
}
