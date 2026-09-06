import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { api, type DuplicateGroup, type LibraryInfo } from "../api";
import { useAuth } from "../auth";
import { CoverMedia } from "../components/CoverMedia";
import { CalmChip } from "../components/CalmChip";
import { EmptyState, InlineError, ListSkeleton } from "../components/UiStates";
import { formatBytes } from "../format";

type ReasonFilter = "all" | "content_hash" | "geometry" | "name_size";
type StatusFilter = "open" | "kept" | "dismissed" | "merged";

const REASON_COPY: Record<string, { label: string; hint: string }> = {
  content_hash: { label: "Exact content", hint: "Same SHA-256 bytes" },
  geometry: { label: "Exact geometry", hint: "Same normalized mesh fingerprint" },
  name_size: { label: "Likely", hint: "Same filename and size" }
};

export function DuplicatesPage() {
  const { user } = useAuth();
  const canReview = Boolean(user?.can_curate || user?.can_merge);
  const [libraries, setLibraries] = useState<LibraryInfo[]>([]);
  const [libraryId, setLibraryId] = useState<number | "">("");
  const [groups, setGroups] = useState<DuplicateGroup[]>([]);
  const [reason, setReason] = useState<ReasonFilter>("all");
  const [status, setStatus] = useState<StatusFilter>("open");
  const [title, setTitle] = useState("Merged duplicates");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [note, setNote] = useState("");
  const [loading, setLoading] = useState(true);
  const [analyzing, setAnalyzing] = useState(false);

  async function loadLibraries() {
    const payload = await api.libraries();
    setLibraries(payload.libraries);
    setLibraryId((current) => current || payload.libraries[0]?.id || "");
  }

  async function loadGroups(id: number, silent = false) {
    if (!silent) setLoading(true);
    const payload = await api.duplicates(id, { status });
    setGroups(payload.groups);
    if (!silent) setLoading(false);
  }

  useEffect(() => {
    loadLibraries().catch((err) => setError(err instanceof Error ? err.message : "Failed to load libraries"));
  }, []);

  useEffect(() => {
    if (libraryId === "") return;
    loadGroups(libraryId).catch((err) => {
      setError(err instanceof Error ? err.message : "Failed to load duplicates");
      setLoading(false);
    });
  }, [libraryId, status]);

  const visible = useMemo(
    () => (reason === "all" ? groups : groups.filter((group) => group.reason === reason)),
    [groups, reason]
  );

  const sections = useMemo(() => {
    const order: Array<DuplicateGroup["reason"]> = ["content_hash", "geometry", "name_size"];
    return order
      .map((key) => ({ key, groups: visible.filter((group) => group.reason === key) }))
      .filter((section) => section.groups.length > 0);
  }, [visible]);

  const counts = useMemo(
    () => ({
      content_hash: groups.filter((group) => group.reason === "content_hash").length,
      geometry: groups.filter((group) => group.reason === "geometry").length,
      name_size: groups.filter((group) => group.reason === "name_size").length
    }),
    [groups]
  );

  async function analyze() {
    if (libraryId === "") return;
    setBusy(true);
    setAnalyzing(true);
    setError(null);
    try {
      await api.analyzeDuplicates(libraryId);
      setNote("Analysis queued. Geometry fingerprints run on path-jailed meshes only.");
      await new Promise((resolve) => window.setTimeout(resolve, 600));
      await loadGroups(libraryId, true);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Analyze failed");
    } finally {
      setBusy(false);
      setAnalyzing(false);
    }
  }

  async function keep(id: number) {
    setBusy(true);
    setError(null);
    try {
      await api.keepDuplicateGroup(id);
      setNote("Kept — files stay on disk.");
      if (libraryId !== "") await loadGroups(libraryId, true);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Keep failed");
    } finally {
      setBusy(false);
    }
  }

  async function dismiss(id: number) {
    setBusy(true);
    setError(null);
    try {
      await api.dismissDuplicateGroup(id);
      setNote("Dismissed — nothing was deleted.");
      if (libraryId !== "") await loadGroups(libraryId, true);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Dismiss failed");
    } finally {
      setBusy(false);
    }
  }

  async function merge(group: DuplicateGroup) {
    const modelIds = [...new Set(group.assets.map((asset) => asset.model_id))];
    if (modelIds.length < 2) {
      setError("Already one model. Keep or dismiss — merge does not delete files.");
      return;
    }
    setBusy(true);
    setError(null);
    try {
      const payload = await api.mergeDuplicateGroup(group.id, {
        title,
        target_id: modelIds[0],
        source_ids: modelIds.slice(1)
      });
      setNote(`Merged into ${payload.model.title}. Files were moved, not deleted.`);
      if (libraryId !== "") await loadGroups(libraryId, true);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Merge failed");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 className="font-display text-3xl text-white">Duplicates</h1>
          <p className="mt-2 max-w-2xl text-sm text-slate-400">
            On-demand review — not part of the scan poll. Exact content is a streamed SHA-256. Exact geometry is a
            normalized, quantized vertex fingerprint (re-exports that hashes miss). Likely is filename + size. Keep and
            dismiss hide a group. Merge uses the existing composer. Nothing here deletes library files.
          </p>
        </div>
        {canReview ? (
          <button
            type="button"
            disabled={busy || libraryId === "" || analyzing}
            onClick={() => void analyze()}
            className="rounded-lg bg-accent-500 px-3 py-1.5 text-sm text-ink-950 disabled:opacity-60"
          >
            {analyzing ? "Analyzing…" : "Analyze library"}
          </button>
        ) : null}
      </div>

      <div className="flex flex-wrap items-end gap-3">
        <label className="text-sm text-slate-300">
          Library
          <select
            className="mt-1 block rounded-lg border border-white/10 bg-ink-950 px-3 py-2"
            value={libraryId}
            onChange={(event) => setLibraryId(Number(event.target.value))}
          >
            {libraries.map((library) => (
              <option key={library.id} value={library.id}>
                {library.name}
              </option>
            ))}
          </select>
        </label>
        {canReview ? (
          <input
            value={title}
            onChange={(event) => setTitle(event.target.value)}
            className="rounded-lg border border-white/10 bg-ink-950 px-3 py-2 text-sm"
            placeholder="Merged folder title"
          />
        ) : null}
      </div>

      <div className="flex flex-wrap items-center gap-2">
        <CalmChip
          active={reason === "all" && status === "open"}
          onClick={() => {
            setReason("all");
            setStatus("open");
          }}
        >
          Open {status === "open" ? groups.length : ""}
        </CalmChip>
        <CalmChip
          active={reason === "content_hash" && status === "open"}
          onClick={() => {
            setReason("content_hash");
            setStatus("open");
          }}
        >
          Exact content {status === "open" ? counts.content_hash : ""}
        </CalmChip>
        <CalmChip
          active={reason === "geometry" && status === "open"}
          onClick={() => {
            setReason("geometry");
            setStatus("open");
          }}
        >
          Exact geometry {status === "open" ? counts.geometry : ""}
        </CalmChip>
        <CalmChip
          active={reason === "name_size" && status === "open"}
          onClick={() => {
            setReason("name_size");
            setStatus("open");
          }}
        >
          Likely {status === "open" ? counts.name_size : ""}
        </CalmChip>
        <CalmChip active={status === "kept"} onClick={() => setStatus(status === "kept" ? "open" : "kept")}>
          Kept
        </CalmChip>
        <CalmChip active={status === "dismissed"} onClick={() => setStatus(status === "dismissed" ? "open" : "dismissed")}>
          Dismissed
        </CalmChip>
      </div>

      {error ? <InlineError message={error} onRetry={libraryId === "" ? undefined : () => void loadGroups(libraryId)} /> : null}
      {note ? <p className="text-sm text-accent-300">{note}</p> : null}

      {loading ? <ListSkeleton rows={3} /> : null}

      {!loading && sections.length === 0 ? (
        <EmptyState
          copy={
            groups.length
              ? "No groups in this filter."
              : "Nothing persisted yet. Owner or contributor: analyze this library to fingerprint meshes and store groups."
          }
        />
      ) : null}

      <div className="space-y-8">
        {sections.map((section) => (
          <section key={section.key}>
            <div className="mb-3">
              <h2 className="font-display text-xl text-white">{REASON_COPY[section.key]?.label || section.key}</h2>
              <p className="text-xs uppercase tracking-wide text-slate-500">{REASON_COPY[section.key]?.hint}</p>
            </div>
            <ul className="space-y-4">
              {section.groups.map((group) => (
                <li key={group.id} className="rounded-2xl border border-white/10 bg-ink-900/70 p-4">
                  <div className="flex flex-wrap items-start justify-between gap-3">
                    <div>
                      <p className="text-sm text-white">
                        {group.filename}
                        <span className="ml-2 text-xs uppercase tracking-wide text-slate-500">
                          {group.confidence} · {group.reason.replace("_", " ")} · {formatBytes(group.byte_size)} ·{" "}
                          {group.assets.length} files
                        </span>
                      </p>
                      {group.digest ? (
                        <p className="mt-1 font-mono text-[11px] text-slate-500">{group.digest}</p>
                      ) : null}
                    </div>
                    {canReview && group.status === "open" ? (
                      <div className="flex flex-wrap gap-2">
                        <button
                          type="button"
                          disabled={busy}
                          onClick={() => void keep(group.id)}
                          className="rounded-lg bg-accent-500 px-3 py-1.5 text-sm text-ink-950 disabled:opacity-60"
                        >
                          Keep
                        </button>
                        <button
                          type="button"
                          disabled={busy}
                          onClick={() => void dismiss(group.id)}
                          className="rounded-lg border border-white/15 px-3 py-1.5 text-sm disabled:opacity-60"
                        >
                          Dismiss
                        </button>
                        {new Set(group.assets.map((asset) => asset.model_id)).size >= 2 ? (
                          <button
                            type="button"
                            disabled={busy}
                            onClick={() => void merge(group)}
                            className="rounded-lg border border-accent-500/40 px-3 py-1.5 text-sm text-accent-300 disabled:opacity-60"
                          >
                            Merge into one model
                          </button>
                        ) : null}
                      </div>
                    ) : (
                      <p className="text-sm text-slate-500">{group.status === "open" ? "View only" : group.status}</p>
                    )}
                  </div>
                  <div className="mt-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
                    {group.assets.map((asset) => (
                      <article key={asset.id} className="overflow-hidden rounded-xl border border-white/5 bg-ink-950/80">
                        <Link to={`/models/${asset.model_id}`} className="block aspect-square">
                          <CoverMedia
                            model={{
                              title: asset.model_title,
                              cover_status: asset.cover_status,
                              cover_url: asset.cover_url,
                              cover_placeholder: asset.cover_placeholder
                            }}
                          />
                        </Link>
                        <div className="space-y-1 p-3">
                          <Link
                            to={`/models/${asset.model_id}`}
                            className="block truncate font-display text-sm text-white hover:text-accent-400"
                          >
                            {asset.model_title}
                          </Link>
                          <p className="truncate text-xs text-slate-300">{asset.filename}</p>
                          <p className="truncate font-mono text-[11px] text-slate-500">{asset.relative_path}</p>
                          <p className="text-[11px] text-slate-500">{formatBytes(asset.byte_size)}</p>
                        </div>
                      </article>
                    ))}
                  </div>
                </li>
              ))}
            </ul>
          </section>
        ))}
      </div>
    </div>
  );
}
