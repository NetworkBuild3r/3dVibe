import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { api, type PrintJob } from "../api";
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

  async function refresh() {
    const payload = await api.printJobs(filter === "all" ? undefined : filter);
    setJobs(payload.print_jobs);
  }

  useEffect(() => {
    refresh().catch((err) => setError(err instanceof Error ? err.message : "Failed to load print jobs"));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [filter]);

  const watching = useMemo(() => jobs.some((job) => ACTIVE.has(job.status)), [jobs]);

  useEffect(() => {
    if (!watching) return;
    const timer = window.setInterval(() => {
      refresh().catch(() => undefined);
    }, 800);
    return () => window.clearInterval(timer);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [watching, filter]);

  async function cancel(id: number) {
    await api.cancelPrint(id);
    await refresh();
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="font-display text-3xl text-white">Print jobs</h1>
        <p className="mt-2 max-w-2xl text-sm text-slate-400">
          Shared queue for the studio library. Status is written by the worker after it path-jails the file and talks to
          the printer adapter.
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

      {error ? <p className="text-sm text-rose-300">{error}</p> : null}

      <section className="rounded-2xl border border-white/10 bg-ink-900/70 p-5">
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
                  {ACTIVE.has(job.status) && (user?.can_manage_printers || user?.id === job.requested_by?.id) ? (
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
          {jobs.length === 0 ? <li className="py-6 text-slate-500">No print jobs in this filter.</li> : null}
        </ul>
      </section>
    </div>
  );
}
