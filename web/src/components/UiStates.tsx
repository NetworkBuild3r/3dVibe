import { Link } from "react-router-dom";

export function Pulse({ className = "" }: { className?: string }) {
  return <div className={`animate-pulse rounded-xl bg-white/5 ${className}`} />;
}

export function SidebarSkeleton({ rows = 5 }: { rows?: number }) {
  return (
    <div className="space-y-3" aria-hidden>
      {Array.from({ length: rows }, (_, index) => (
        <Pulse key={index} className="h-14 w-full" />
      ))}
    </div>
  );
}

export function CardGridSkeleton({ cards = 8 }: { cards?: number }) {
  return (
    <div className="card-grid" aria-hidden>
      {Array.from({ length: cards }, (_, index) => (
        <div key={index}>
          <Pulse className="aspect-square" />
          <Pulse className="mt-2.5 h-4 w-3/4" />
          <Pulse className="mt-2 h-3 w-1/2" />
        </div>
      ))}
    </div>
  );
}

export function ListSkeleton({ rows = 4 }: { rows?: number }) {
  return (
    <ul className="divide-y divide-white/5" aria-hidden>
      {Array.from({ length: rows }, (_, index) => (
        <li key={index} className="py-4">
          <Pulse className="h-4 w-1/2" />
          <Pulse className="mt-2 h-3 w-1/3" />
          <Pulse className="mt-3 h-1.5 w-full rounded-full" />
        </li>
      ))}
    </ul>
  );
}

export function InlineError({ message, onRetry }: { message: string; onRetry?: () => void }) {
  return (
    <div className="flex flex-wrap items-center gap-3 text-sm text-rose-300">
      <p>{message}</p>
      {onRetry ? (
        <button type="button" className="text-accent-400 hover:text-accent-300" onClick={onRetry}>
          Retry
        </button>
      ) : null}
    </div>
  );
}

export function EmptyState({
  copy,
  ctaTo,
  ctaLabel
}: {
  copy: string;
  ctaTo?: string;
  ctaLabel?: string;
}) {
  return (
    <div className="rounded-2xl border border-dashed border-white/10 px-4 py-8 text-center">
      <p className="text-sm text-slate-400">{copy}</p>
      {ctaTo && ctaLabel ? (
        <Link to={ctaTo} className="mt-3 inline-block text-sm text-accent-400 hover:text-accent-300">
          {ctaLabel}
        </Link>
      ) : null}
    </div>
  );
}
