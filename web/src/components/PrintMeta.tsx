import { protocolKind, protocolLabel, jobProgressClass, jobStatusClass, jobStatusLabel } from "../prints";

export function ProtocolChip({ protocol }: { protocol?: string | null }) {
  const kind = protocolKind(protocol);
  return (
    <span
      className={`inline-flex rounded-full border px-2 py-0.5 text-[11px] uppercase tracking-wide ${
        kind === "sdcp" ? "border-amber-400/30 text-amber-200" : "border-white/10 text-slate-400"
      }`}
    >
      {protocolLabel(protocol)}
    </span>
  );
}

export function JobStatus({ status, progress }: { status?: string | null; progress?: number | null }) {
  const pct = typeof progress === "number" ? ` · ${progress}%` : "";
  return (
    <p className={`text-sm font-medium ${jobStatusClass(status)}`}>
      {jobStatusLabel(status)}
      {pct}
    </p>
  );
}

export function JobProgress({ status, progress }: { status?: string | null; progress?: number | null }) {
  const width = Math.max(0, Math.min(100, progress ?? 0));
  return (
    <div className="h-1.5 overflow-hidden rounded-full bg-white/5">
      <div className={`h-full rounded-full ${jobProgressClass(status)}`} style={{ width: `${width}%` }} />
    </div>
  );
}
