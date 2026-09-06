import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { api, type PrintJob } from "../api";
import { InlineError, ListSkeleton } from "../components/UiStates";
import { useAuth } from "../auth";

const FILTERS = [
  { id: "all", label: "All" },
  { id: "queued", label: "Queued" },
  { id: "sending", label: "Sending" },
  { id: "printing", label: "Printing" },
  { id: "succeeded", label: "Succeeded" },
  { id: "failed", label: "Failed" },
  { id: "cancelled", label: "Cancelled" }
] as const;

const ACTIVE = new Set(["queued", "sending", "printing"]);

function statusClass(status: string) {
  if (status === "succeeded") return "text-accent-400";
  if (status === "failed") return "text-rose-300";
  if (status === "cancelled") return "text-slate-500";
  return "text-amber-200";
}

export function PrintsPage() {
  const { user } = useAuth();
  const [jobs, setJobs] = useState<PrintJob[]>([]);
  const [filter, setFilter] = useState<(typeof FILTERS)[number]["id"]>("all");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  async function refresh(options: { silent?: boolean } = {}) {
    if (!options.silent) {
      setError(null);
      setLoading(true);
    }
    try {
      const payload = await api.printJobs(filter === "all" ? undefined : filter);
      setJobs(payload.print_jobs);
      if (!options.silent) setError(null);
    } catch (err) {
      if (!options.silent) {
        setError(err instanceof Error ? err.message : "Failed to load print jobs");
      }
    } finally {
      if (!options.silent) setLoading(false);
    }
  }

  useEffect(() => {
    setJobs([]);
    void refresh();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [filter]);

  const watching = useMemo(() => jobs.some((job) => ACTIVE.has(job.status)), [jobs]);

  useEffect(() => {
    if (!watching) return;
    const timer = window.setInterval(() => {
      void refresh({ silent: true });
    }, 800);
    return () => window.clearInterval(timer);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [watching, filter]);

  async function cancel(id: number) {
    setError(null);
    try {
      await api.cancelPrint(id);
      await refresh({ silent: true });
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not cancel print");
    }
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="font-display text-3xl text-white">Your print history</h1>
        <p className="mt-2 max-w-2xl text-sm text-slate-400">
          Only you can see jobs you queued. Sending a file to a printer is limited to the library owner; contributors
          and viewers can still share into the catalog. Status is written by the worker after it path-jails the file.
        </p>
      </div>

      <div className="flex flex-wrap gap-2">
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
      </div>

      {error ? <InlineError message={error} onRetry={() => void refresh()} /> : null}

      <section className="rounded-2xl border border-white/10 bg-ink-900/70 p-5" aria-busy={loading}>
        {loading ? (
          <ListSkeleton />
        ) : (
          <ul className="divide-y divide-white/5">
            {jobs.map((job) => (
              <li key={job.id} className="py-4">
                <div className="flex flex-wrap items-start justify-between gap-3">
                  <div>
                    <p className="text-slate-100">
                      {job.model_id ? (
                        <Link to={`/models/${job.model_id}`} className="hover:text-accent-400">
                          {job.model_title || `Model ${job.model_id}`}
                        </Link>
                      ) : (
                        "Unknown model"
                      )}
                      <span className="ml-2 font-mono text-xs text-slate-500">{job.filename || "file"}</span>
                    </p>
                    <p className="mt-1 text-xs text-slate-500">
                      {job.printer_name || "printer"} · {job.protocol_type || "adapter"}
                      {job.requested_by ? ` · ${job.requested_by.display_name}` : ""}
                      {` · ${new Date(job.created_at).toLocaleString()}`}
                    </p>
                    {job.note ? <p className="mt-2 text-sm text-slate-400">{job.note}</p> : null}
                    {job.error_message ? <p className="mt-1 text-sm text-rose-300">{job.error_message}</p> : null}
                  </div>
                  <div className="text-right">
                    <p className={`text-sm font-medium ${statusClass(job.status)}`}>
                      {job.status} · {job.progress}%
                    </p>
                    {ACTIVE.has(job.status) && user?.id === job.requested_by?.id ? (
                      <button type="button" className="mt-2 text-xs text-rose-300" onClick={() => void cancel(job.id)}>
                        Cancel
                      </button>
                    ) : null}
                  </div>
                </div>
                <div className="mt-3 h-1.5 overflow-hidden rounded-full bg-white/5">
                  <div className="h-full rounded-full bg-accent-500" style={{ width: `${job.progress}%` }} />
                </div>
              </li>
            ))}
            {jobs.length === 0 ? <li className="py-6 text-slate-500">No jobs in this filter.</li> : null}
          </ul>
        )}
      </section>
    </div>
  );
}
