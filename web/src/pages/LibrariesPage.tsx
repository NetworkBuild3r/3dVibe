import { useEffect, useState } from "react";
import { api, type LibraryInfo, type ScanStatus } from "../api";

function formatWhen(value?: string | null) {
  if (!value) return "—";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "—";
  return date.toLocaleString();
}

function statusTone(status?: string) {
  switch (status) {
    case "running":
    case "queued":
      return "text-accent-400";
    case "budgeted":
      return "text-amber-300";
    case "failed":
      return "text-rose-300";
    case "completed":
      return "text-emerald-300";
    default:
      return "text-slate-400";
  }
}

function scanSummary(scan?: ScanStatus) {
  if (!scan || scan.status === "idle") return "No scan has run yet.";
  const files = scan.files_seen ?? 0;
  const errors = scan.error_count ?? 0;
  const pruned = scan.pruned_count ?? 0;
  return `${files} files seen · ${scan.folders_indexed ?? 0} folders indexed · ${scan.folders_skipped ?? 0} skipped · ${pruned} pruned · ${errors} errors`;
}

export function LibrariesPage() {
  const [libraries, setLibraries] = useState<LibraryInfo[]>([]);
  const [selectedId, setSelectedId] = useState<number | "">("");
  const [detail, setDetail] = useState<LibraryInfo | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function refreshList() {
    const payload = await api.libraries();
    setLibraries(payload.libraries);
    if (selectedId === "" && payload.libraries[0]) setSelectedId(payload.libraries[0].id);
  }

  async function refreshDetail(id: number) {
    const payload = await api.library(id);
    setDetail(payload.library);
  }

  useEffect(() => {
    refreshList().catch((err) => setError(err instanceof Error ? err.message : "Failed to load libraries"));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    if (selectedId === "") {
      setDetail(null);
      return;
    }
    refreshDetail(selectedId).catch((err) => setError(err instanceof Error ? err.message : "Failed to load library"));
  }, [selectedId]);

  const active = detail?.scan?.status === "running" || detail?.scan?.status === "queued" || detail?.scan?.status === "budgeted";

  useEffect(() => {
    if (!active || selectedId === "") return;
    const timer = window.setInterval(() => {
      refreshDetail(selectedId).catch(() => undefined);
      refreshList().catch(() => undefined);
    }, 3000);
    return () => window.clearInterval(timer);
  }, [active, selectedId]);

  async function scanNow() {
    if (selectedId === "") return;
    setBusy(true);
    setError(null);
    try {
      const payload = await api.scanLibrary(selectedId);
      setDetail(payload.library);
      await refreshList();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not queue scan");
    } finally {
      setBusy(false);
    }
  }

  const settings = detail?.scan_settings;

  return (
    <div className="space-y-8">
      <div>
        <h1 className="font-display text-3xl text-white">Libraries</h1>
        <p className="mt-2 max-w-2xl text-sm text-slate-400">
          NFS incremental scan status for the owner. Recurring Sidekiq cron walks the mount with mtime/size/inode
          cursors, time and file budgets, and batched prune. inotify is not used.
        </p>
      </div>

      <section className="rounded-2xl border border-white/10 bg-ink-900/70 p-5">
        <h2 className="font-display text-xl text-white">Catalogs</h2>
        <ul className="mt-4 divide-y divide-white/5">
          {libraries.map((library) => (
            <li key={library.id}>
              <button
                type="button"
                onClick={() => setSelectedId(library.id)}
                className={`flex w-full flex-wrap items-center justify-between gap-3 py-3 text-left text-sm ${
                  selectedId === library.id ? "text-white" : "text-slate-300"
                }`}
              >
                <div>
                  <p>
                    {library.name}
                    <span className="ml-2 text-xs uppercase tracking-wide text-slate-500">{library.role}</span>
                  </p>
                  <p className="text-xs text-slate-500">
                    {library.root_path} · {library.model_count} models
                  </p>
                </div>
                <span className={`text-xs uppercase tracking-wide ${statusTone(library.scan?.status)}`}>
                  {library.scan?.status || "idle"}
                </span>
              </button>
            </li>
          ))}
          {libraries.length === 0 ? <li className="py-3 text-slate-500">No libraries yet.</li> : null}
        </ul>
      </section>

      {detail ? (
        <section className="rounded-2xl border border-white/10 bg-ink-900/70 p-5">
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div>
              <h2 className="font-display text-xl text-white">{detail.name}</h2>
              <p className="mt-1 text-xs text-slate-500">{detail.root_path}</p>
            </div>
            <button
              type="button"
              onClick={() => void scanNow()}
              disabled={busy || !detail.can_scan}
              className="rounded-lg bg-accent-500 px-4 py-2 text-sm font-medium text-ink-950 hover:bg-accent-400 disabled:opacity-60"
            >
              {busy ? "Queueing…" : "Scan now"}
            </button>
          </div>

          <dl className="mt-5 grid gap-4 text-sm md:grid-cols-2">
            <div>
              <dt className="text-slate-500">Status</dt>
              <dd className={`mt-1 capitalize ${statusTone(detail.scan?.status)}`}>{detail.scan?.status || "idle"}</dd>
            </div>
            <div>
              <dt className="text-slate-500">Trigger</dt>
              <dd className="mt-1 text-slate-200">{detail.scan?.trigger || "—"}</dd>
            </div>
            <div>
              <dt className="text-slate-500">Last started</dt>
              <dd className="mt-1 text-slate-200">{formatWhen(detail.scan?.started_at)}</dd>
            </div>
            <div>
              <dt className="text-slate-500">Last finished</dt>
              <dd className="mt-1 text-slate-200">{formatWhen(detail.scan?.finished_at)}</dd>
            </div>
            <div className="md:col-span-2">
              <dt className="text-slate-500">This run</dt>
              <dd className="mt-1 text-slate-200">{scanSummary(detail.scan)}</dd>
            </div>
            {detail.scan?.resume_after ? (
              <div className="md:col-span-2">
                <dt className="text-slate-500">Resume after</dt>
                <dd className="mt-1 text-amber-200">{detail.scan.resume_after}</dd>
              </div>
            ) : null}
            {detail.scan?.last_error ? (
              <div className="md:col-span-2">
                <dt className="text-slate-500">Last error</dt>
                <dd className="mt-1 text-rose-300">{detail.scan.last_error}</dd>
              </div>
            ) : null}
            <div>
              <dt className="text-slate-500">Curation last poll</dt>
              <dd className="mt-1 text-slate-200">{formatWhen(detail.curation?.last_polled_at)}</dd>
            </div>
            <div>
              <dt className="text-slate-500">Curation provider</dt>
              <dd className="mt-1 text-slate-200">{detail.curation?.last_provider || "—"}</dd>
            </div>
            {detail.curation?.last_error ? (
              <div className="md:col-span-2">
                <dt className="text-slate-500">Curation last error</dt>
                <dd className="mt-1 text-rose-300">{detail.curation.last_error}</dd>
              </div>
            ) : null}
          </dl>

          {settings ? (
            <p className="mt-5 text-xs text-slate-500">
              Schedule {settings.schedule ? settings.cron : "off"} · {settings.max_seconds}s / {settings.max_files}{" "}
              files / {settings.max_folders} folders per job · prune {settings.prune_batch} · deep every{" "}
              {Math.round(settings.deep_interval / 3600)}h
            </p>
          ) : null}

          {detail.cursors && detail.cursors.length > 0 ? (
            <div className="mt-6">
              <h3 className="text-sm text-slate-400">Folder cursors</h3>
              <ul className="mt-2 max-h-56 overflow-auto divide-y divide-white/5 text-xs text-slate-500">
                {detail.cursors.map((cursor) => (
                  <li key={cursor.path_prefix} className="flex justify-between gap-3 py-1.5">
                    <span className="text-slate-300">{cursor.path_prefix}</span>
                    <span>
                      {cursor.last_file_count ?? "?"} files · scanned {formatWhen(cursor.last_scanned_at)}
                      {cursor.resume_relative_path ? ` · resume ${cursor.resume_relative_path}` : ""}
                    </span>
                  </li>
                ))}
              </ul>
            </div>
          ) : null}
        </section>
      ) : null}

      {error ? <p className="text-sm text-rose-300">{error}</p> : null}
    </div>
  );
}
