import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { api, type CurationProposal, type LibraryInfo } from "../api";
import { useAuth } from "../auth";

const FILTERS = [
  { id: "pending", label: "Pending" },
  { id: "approved", label: "Approved" },
  { id: "rejected", label: "Rejected" },
  { id: "all", label: "All" }
] as const;

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
        {preview?.filesystem ? <p className="mt-2 text-xs text-amber-300">Filesystem change (path-jailed)</p> : null}
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

export function CurationPage() {
  const { user } = useAuth();
  const canCurate = Boolean(user?.can_curate);
  const [proposals, setProposals] = useState<CurationProposal[]>([]);
  const [libraries, setLibraries] = useState<LibraryInfo[]>([]);
  const [filter, setFilter] = useState<(typeof FILTERS)[number]["id"]>("pending");
  const [selected, setSelected] = useState<number[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const visible = useMemo(
    () => (filter === "all" ? proposals : proposals.filter((proposal) => proposal.status === filter)),
    [filter, proposals]
  );
  const pendingIds = visible.filter((proposal) => proposal.status === "pending").map((proposal) => proposal.id);

  async function refresh() {
    const [proposalPayload, libraryPayload] = await Promise.all([api.proposals(), api.libraries()]);
    setProposals(proposalPayload.proposals);
    setLibraries(libraryPayload.libraries);
    setSelected((current) => current.filter((id) => proposalPayload.proposals.some((item) => item.id === id && item.status === "pending")));
  }

  useEffect(() => {
    refresh().catch((err) => setError(err instanceof Error ? err.message : "Failed"));
  }, []);

  async function act(id: number, action: "approve" | "reject") {
    setBusy(true);
    setError(null);
    try {
      if (action === "approve") await api.approveProposal(id);
      else await api.rejectProposal(id);
      await refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Action failed");
    } finally {
      setBusy(false);
    }
  }

  async function bulk(action: "approve" | "reject") {
    if (!selected.length) return;
    setBusy(true);
    setError(null);
    try {
      await api.bulkProposals(selected, action);
      setSelected([]);
      await refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Bulk action failed");
    } finally {
      setBusy(false);
    }
  }

  async function fetchFromSidecar() {
    const libraryId = libraries[0]?.id;
    if (!libraryId) {
      setError("No library to curate");
      return;
    }
    setBusy(true);
    setError(null);
    try {
      await api.fetchProposals(libraryId);
      await refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not fetch proposals");
    } finally {
      setBusy(false);
    }
  }

  function toggle(id: number) {
    setSelected((current) => (current.includes(id) ? current.filter((item) => item !== id) : [...current, id]));
  }

  function toggleAll() {
    setSelected((current) => (current.length === pendingIds.length ? [] : pendingIds));
  }

  return (
    <div>
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 className="font-display text-3xl text-white">Curation queue</h1>
          <p className="mt-1 max-w-2xl text-sm text-slate-400">
            Human review of sidecar suggestions. Tags apply immediately. Rename, move, and merge stay inside the library
            path jail and rescan the touched folders. Spark/DGX is optional — the stub curator is enough for this loop.
          </p>
        </div>
        {canCurate ? (
          <button
            type="button"
            disabled={busy}
            onClick={() => void fetchFromSidecar()}
            className="rounded-lg bg-accent-500 px-3 py-1.5 text-sm text-ink-950 disabled:opacity-60"
          >
            {busy ? "Working…" : "Fetch proposals"}
          </button>
        ) : null}
      </div>

      <div className="mt-5 flex flex-wrap items-center gap-2">
        {FILTERS.map((item) => (
          <button
            key={item.id}
            type="button"
            onClick={() => setFilter(item.id)}
            className={`rounded-full px-3 py-1 text-sm ${
              filter === item.id ? "bg-accent-500/15 text-accent-400" : "text-slate-400 hover:text-white"
            }`}
          >
            {item.label}
          </button>
        ))}
        {canCurate && pendingIds.length ? (
          <>
            <button type="button" className="ml-2 text-sm text-slate-400 hover:text-white" onClick={toggleAll}>
              {selected.length === pendingIds.length ? "Clear" : "Select pending"}
            </button>
            <button
              type="button"
              disabled={busy || !selected.length}
              onClick={() => void bulk("approve")}
              className="rounded-lg bg-accent-500 px-3 py-1 text-sm text-ink-950 disabled:opacity-50"
            >
              Approve selected
            </button>
            <button
              type="button"
              disabled={busy || !selected.length}
              onClick={() => void bulk("reject")}
              className="rounded-lg border border-white/15 px-3 py-1 text-sm disabled:opacity-50"
            >
              Reject selected
            </button>
          </>
        ) : null}
      </div>

      {error ? <p className="mt-4 text-rose-300">{error}</p> : null}

      <div className="mt-6 space-y-3">
        {visible.map((proposal) => (
          <article key={proposal.id} className="rounded-2xl border border-white/10 bg-ink-900/70 p-4">
            <div className="flex flex-wrap items-start justify-between gap-3">
              <div className="min-w-0 flex-1">
                <div className="flex flex-wrap items-center gap-2">
                  {canCurate && proposal.status === "pending" ? (
                    <input
                      type="checkbox"
                      className="mt-0.5"
                      checked={selected.includes(proposal.id)}
                      onChange={() => toggle(proposal.id)}
                      aria-label={`Select ${proposal.summary}`}
                    />
                  ) : null}
                  <p className="text-xs uppercase tracking-wide text-slate-500">
                    {proposal.kind} · {proposal.status}
                    {proposal.sidecar_ref ? ` · ${proposal.sidecar_ref}` : ""}
                  </p>
                </div>
                <h2 className="mt-1 text-lg text-white">{proposal.summary}</h2>
                <Preview proposal={proposal} />
                {proposal.apply_error ? <p className="mt-2 text-sm text-rose-300">Apply failed: {proposal.apply_error}</p> : null}
                {proposal.applied_at ? (
                  <p className="mt-2 text-xs text-slate-500">Applied {new Date(proposal.applied_at).toLocaleString()}</p>
                ) : null}
              </div>
              {proposal.status === "pending" && canCurate ? (
                <div className="flex gap-2">
                  <button
                    type="button"
                    disabled={busy}
                    onClick={() => void act(proposal.id, "approve")}
                    className="rounded-lg bg-accent-500 px-3 py-1.5 text-sm text-ink-950 disabled:opacity-60"
                  >
                    Approve
                  </button>
                  <button
                    type="button"
                    disabled={busy}
                    onClick={() => void act(proposal.id, "reject")}
                    className="rounded-lg border border-white/15 px-3 py-1.5 text-sm disabled:opacity-60"
                  >
                    Reject
                  </button>
                </div>
              ) : (
                <p className="text-sm text-slate-500">{proposal.status === "pending" ? "View only" : "Reviewed"}</p>
              )}
            </div>
          </article>
        ))}
        {visible.length === 0 ? (
          <p className="text-slate-500">
            No {filter === "all" ? "" : `${filter} `}proposals yet.
            {canCurate ? " Fetch from the sidecar to generate a deterministic fixture batch." : ""}
          </p>
        ) : null}
      </div>
    </div>
  );
}
