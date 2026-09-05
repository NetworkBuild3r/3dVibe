import { useCallback, useEffect, useRef, useState } from "react";
import { Link } from "react-router-dom";
import { api, type ModelCard } from "../api";

function formatBytes(value: number) {
  if (value < 1024) return `${value} B`;
  if (value < 1024 * 1024) return `${(value / 1024).toFixed(1)} KB`;
  return `${(value / (1024 * 1024)).toFixed(1)} MB`;
}

export function GalleryPage() {
  const [models, setModels] = useState<ModelCard[]>([]);
  const [hasMore, setHasMore] = useState(true);
  const [loading, setLoading] = useState(false);
  const [query, setQuery] = useState("");
  const [status, setStatus] = useState("");
  const sentinel = useRef<HTMLDivElement | null>(null);
  const queryRef = useRef("");
  const cursorRef = useRef<string | null>(null);
  const hasMoreRef = useRef(true);
  const loadingRef = useRef(false);

  const loadMore = useCallback(async () => {
    if (loadingRef.current || !hasMoreRef.current || queryRef.current.trim()) return;
    loadingRef.current = true;
    setLoading(true);
    setStatus("Loading more…");
    try {
      const page = await api.models(cursorRef.current);
      setModels((current) => {
        const seen = new Set(current.map((item) => item.id));
        return [...current, ...page.models.filter((item) => !seen.has(item.id))];
      });
      const next = page.next_cursor ? String(page.next_cursor) : null;
      cursorRef.current = next;
      hasMoreRef.current = Boolean(next);
      setHasMore(Boolean(next));
      setStatus(next ? "" : "End of library");
    } finally {
      loadingRef.current = false;
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void loadMore();
  }, [loadMore]);

  useEffect(() => {
    if (!sentinel.current) return;
    const node = sentinel.current;
    const observer = new IntersectionObserver((entries) => {
      if (entries.some((entry) => entry.isIntersecting)) void loadMore();
    });
    observer.observe(node);
    return () => observer.disconnect();
  }, [loadMore]);

  async function runSearch(value: string) {
    setQuery(value);
    queryRef.current = value;
    if (!value.trim()) {
      setModels([]);
      cursorRef.current = null;
      hasMoreRef.current = true;
      setHasMore(true);
      await loadMore();
      return;
    }
    setStatus("Searching…");
    const result = await api.search(value);
    setModels(result.models);
    hasMoreRef.current = false;
    setHasMore(false);
    setStatus(result.models.length ? `Postgres search · ${result.engine}` : "No matches");
  }

  return (
    <div>
      <div className="mb-6 flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 className="font-display text-3xl text-white">Library</h1>
          <p className="mt-1 text-sm text-slate-400">Browse folders on disk. Cards never auto-load meshes.</p>
        </div>
        <input
          value={query}
          onChange={(event) => void runSearch(event.target.value)}
          placeholder="Search title, folder, tags…"
          className="w-full max-w-sm rounded-full border border-white/10 bg-ink-900 px-4 py-2 text-sm outline-none ring-accent-500 focus:ring-2"
        />
      </div>
      <div className="card-grid">
        {models.map((model) => (
          <Link
            key={model.id}
            to={`/models/${model.id}`}
            className="group rounded-2xl border border-white/10 bg-ink-900/70 p-4 transition hover:-translate-y-0.5 hover:border-accent-500/40"
          >
            <div className="mb-4 grid h-28 place-items-center rounded-xl bg-ink-800 text-xs uppercase tracking-widest text-slate-500">
              Mesh idle
            </div>
            <h2 className="font-display text-lg text-white group-hover:text-accent-400">{model.title}</h2>
            <p className="mt-1 line-clamp-2 text-sm text-slate-400">{model.synopsis || model.folder_name}</p>
            <div className="mt-3 flex flex-wrap gap-1.5">
              {model.tags.slice(0, 4).map((tag) => (
                <span key={tag} className="rounded-full bg-white/5 px-2 py-0.5 text-xs text-slate-300">
                  {tag}
                </span>
              ))}
            </div>
            <p className="mt-3 text-xs text-slate-500">
              {model.asset_count} files · {formatBytes(model.byte_size)}
            </p>
          </Link>
        ))}
      </div>
      <div ref={sentinel} className="h-10" />
      <p className="py-4 text-center text-sm text-slate-500">
        {loading ? "Loading more…" : status || (hasMore ? "" : "End of library")}
      </p>
    </div>
  );
}
