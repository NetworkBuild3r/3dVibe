import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { api, type PrintJob } from "../api";
import { CalmChip } from "../components/CalmChip";
import { JobProgress, JobStatus, ProtocolChip } from "../components/PrintMeta";
import { EmptyState, InlineError, ListSkeleton } from "../components/UiStates";
import { useAuth } from "../auth";
import { formatRelativeTime } from "../format";
import {
  HISTORY_COPY,
  JOB_FILTERS,
  canCancelJob,
  canRetryJob,
  emptyPrintsCopy,
  isJobActive,
  type JobFilter
} from "../prints";

export function PrintsPage() {
  const { user } = useAuth();
  const [jobs, setJobs] = useState<PrintJob[]>([]);
  const [filter, setFilter] = useState<JobFilter>("all");
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

  const watching = useMemo(() => jobs.some((job) => isJobActive(job.status)), [jobs]);

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

  async function retry(id: number) {
    setError(null);
    try {
      await api.retryPrint(id);
      await refresh({ silent: true });
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not retry print");
    }
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="font-display text-3xl text-white">Your print history</h1>
        <p className="mt-2 max-w-2xl text-sm text-slate-400">{HISTORY_COPY}</p>
      </div>

      <div className="flex flex-wrap gap-2">
        {JOB_FILTERS.map((item) => (
          <CalmChip key={item.id} active={filter === item.id} onClick={() => setFilter(item.id)}>
            {item.label}
          </CalmChip>
        ))}
      </div>

      {error ? <InlineError message={error} onRetry={() => void refresh()} /> : null}

      <section className="rounded-2xl border border-white/10 bg-ink-900/70 p-5" aria-busy={loading}>
        {loading ? (
          <ListSkeleton />
        ) : jobs.length === 0 ? (
          <EmptyState copy={emptyPrintsCopy(filter)} ctaTo="/" ctaLabel="Browse library" />
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
                    <div className="mt-2 flex flex-wrap items-center gap-2 text-xs text-slate-500">
                      <span>{job.printer_name || "printer"}</span>
                      <ProtocolChip protocol={job.protocol_type} />
                      <span>{formatRelativeTime(job.created_at) || new Date(job.created_at).toLocaleString()}</span>
                      {job.requested_by ? <span>{job.requested_by.display_name}</span> : null}
                    </div>
                    {job.note ? <p className="mt-2 text-sm text-slate-400">{job.note}</p> : null}
                    {job.error_message ? <p className="mt-1 text-sm text-rose-300">{job.error_message}</p> : null}
                  </div>
                  <div className="text-right">
                    <JobStatus status={job.status} progress={job.progress} />
                    {canCancelJob(job, user?.id) ? (
                      <button type="button" className="mt-2 text-xs text-rose-300" onClick={() => void cancel(job.id)}>
                        Cancel
                      </button>
                    ) : null}
                    {canRetryJob(job, user?.can_print) ? (
                      <button
                        type="button"
                        className={`mt-2 block text-xs ${job.status === "failed" ? "text-rose-300" : "text-accent-400"}`}
                        onClick={() => void retry(job.id)}
                      >
                        Retry
                      </button>
                    ) : null}
                  </div>
                </div>
                <div className="mt-3">
                  <JobProgress status={job.status} progress={job.progress} />
                </div>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
