import type { Creator } from "../api";

export function CreatorHeader({ creator }: { creator: Creator }) {
  const count = creator.model_count ?? 0;

  return (
    <header className="rounded-2xl border border-white/5 bg-gradient-to-br from-accent-500/10 via-ink-900/40 to-transparent px-5 py-5">
      <h1 className="font-display text-3xl text-white">{creator.name}</h1>
      <p className="mt-1 text-sm text-slate-400">/{creator.slug}</p>
      <p className="mt-3 text-sm text-slate-300">
        {count} model{count === 1 ? "" : "s"}
      </p>
    </header>
  );
}
