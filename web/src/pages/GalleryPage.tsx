import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { Link } from "react-router-dom";
import { api, type ModelCard } from "../api";

const PAGE_SIZE = 18;
const SEARCH_DEBOUNCE_MS = 280;

function formatBytes(value: number) {
  if (value < 1024) return `${value} B`;
  if (value < 1024 * 1024) return `${(value / 1024).toFixed(1)} KB`;
  return `${(value / (1024 * 1024)).toFixed(1)} MB`;
}

function searching(query: string, tag: string, preview: boolean) {
  return Boolean(query.trim() || tag || preview);
}

export function GalleryPage() {
  const [models, setModels] = useState<ModelCard[]>([]);
  const [hasMore, setHasMore] = useState(true);
  const [loading, setLoading] = useState(false);
  const [query, setQuery] = useState("");
  const [tag, setTag] = useState("");
  const [hasPreview, setHasPreview] = useState(false);
  const [status, setStatus] = useState("");
  const [engine, setEngine] = useState("");
  const [facetTags, setFacetTags] = useState<Record<string, number>>({});
  const sentinel = useRef<HTMLDivElement | null>(null);
  const queryRef = useRef("");
  const tagRef = useRef("");
  const previewRef = useRef(false);
  const cursorRef = useRef<string | null>(null);
  const offsetRef = useRef(0);
  const hasMoreRef = useRef(true);
  const loadingRef = useRef(false);
  const requestRef = useRef(0);

  const activeSearch = searching(query, tag, hasPreview);

  const tagOptions = useMemo(() => {
    const counts = { ...facetTags };
    models.forEach((model) => {
      model.tags.forEach((name) => {
        if (counts[name] == null) counts[name] = 0;
      });
    });
    return Object.entries(counts).sort((a, b) => a[0].localeCompare(b[0]));
  }, [facetTags, models]);

  const loadMore = useCallback(async () => {
    if (loadingRef.current || !hasMoreRef.current) return;
    const q = queryRef.current.trim();
    const selectedTag = tagRef.current;
    const previewOnly = previewRef.current;
    const useSearch = searching(q, selectedTag, previewOnly);
    const ticket = ++requestRef.current;

    loadingRef.current = true;
    setLoading(true);
    setStatus("Loading more…");
    try {
      if (useSearch) {
        const page = await api.search({
          q,
          tag: selectedTag || undefined,
          has_preview: previewOnly ? true : "",
          offset: offsetRef.current,
          limit: PAGE_SIZE
        });
        if (ticket !== requestRef.current) return;
        setModels((current) => {
          const seen = new Set(current.map((item) => item.id));
          return [...current, ...page.models.filter((item) => !seen.has(item.id))];
        });
        setFacetTags(page.facets?.tags || {});
        offsetRef.current = page.next_offset ?? offsetRef.current + page.models.length;
        hasMoreRef.current = page.next_offset != null;
        setHasMore(page.next_offset != null);
        const label = page.fallback ? `${page.engine} fallback` : page.engine;
        setEngine(label);
        setStatus(
          page.models.length || offsetRef.current
            ? `${label} · ${page.estimated_total} match${page.estimated_total === 1 ? "" : "es"}`
            : "No matches"
        );
      } else {
        const page = await api.models(cursorRef.current, PAGE_SIZE);
        if (ticket !== requestRef.current) return;
        setModels((current) => {
          const seen = new Set(current.map((item) => item.id));
          return [...current, ...page.models.filter((item) => !seen.has(item.id))];
        });
        const next = page.next_cursor ? String(page.next_cursor) : null;
        cursorRef.current = next;
        hasMoreRef.current = Boolean(next);
        setHasMore(Boolean(next));
        setEngine("");
        setStatus(next ? "" : "End of library");
      }
    } finally {
      if (ticket === requestRef.current) {
        loadingRef.current = false;
        setLoading(false);
      }
    }
  }, []);

  const resetAndLoad = useCallback(() => {
    requestRef.current += 1;
    setModels([]);
    cursorRef.current = null;
    offsetRef.current = 0;
    hasMoreRef.current = true;
    setHasMore(true);
    loadingRef.current = false;
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

  useEffect(() => {
    queryRef.current = query;
    tagRef.current = tag;
    previewRef.current = hasPreview;
    const handle = window.setTimeout(() => {
      resetAndLoad();
    }, SEARCH_DEBOUNCE_MS);
    return () => window.clearTimeout(handle);
  }, [query, tag, hasPreview, resetAndLoad]);

  function toggleTag(name: string) {
    setTag((current) => (current === name ? "" : name));
  }

  return (
    <div>
      <div className="mb-6 flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 className="font-display text-3xl text-white">Library</h1>
          <p className="mt-1 text-sm text-slate-400">
            One shared catalog. Every signed-in friend sees the same folders. Cards never auto-load meshes.
          </p>
        </div>
        <input
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          placeholder="Search title, folder, tags, files…"
          className="w-full max-w-sm rounded-full border border-white/10 bg-ink-900 px-4 py-2 text-sm outline-none ring-accent-500 focus:ring-2"
        />
      </div>
      <div className="mb-5 flex flex-wrap items-center gap-2">
        <button
          type="button"
          onClick={() => setHasPreview((current) => !current)}
          className={`rounded-full px-3 py-1 text-xs ${
            hasPreview ? "bg-accent-500/20 text-accent-300" : "bg-white/5 text-slate-400"
          }`}
        >
          Has preview
        </button>
        {tagOptions.slice(0, 12).map(([name, count]) => (
          <button
            key={name}
            type="button"
            onClick={() => toggleTag(name)}
            className={`rounded-full px-3 py-1 text-xs ${
              tag === name ? "bg-accent-500/20 text-accent-300" : "bg-white/5 text-slate-400"
            }`}
          >
            {name}
            {count ? <span className="ml-1 text-slate-500">{count}</span> : null}
          </button>
        ))}
        {activeSearch && engine ? <span className="ml-auto text-xs text-slate-500">{engine}</span> : null}
      </div>
      <div className="card-grid">
        {models.map((model) => (
          <Link
            key={model.id}
            to={`/models/${model.id}`}
            className="group rounded-2xl border border-white/10 bg-ink-900/70 p-4 transition hover:-translate-y-0.5 hover:border-accent-500/40"
          >
            <div className="mb-4 grid h-28 place-items-center rounded-xl bg-ink-800 text-xs uppercase tracking-widest text-slate-500">
              {model.has_preview ? "Preview ready" : "Mesh idle"}
            </div>
            <h2 className="font-display text-lg text-white group-hover:text-accent-400">{model.title}</h2>
            <p className="mt-1 line-clamp-2 text-sm text-slate-400">{model.synopsis || model.folder_name}</p>
            <div className="mt-3 flex flex-wrap gap-1.5">
              {model.tags.slice(0, 4).map((name) => (
                <span
                  key={name}
                  className="rounded-full bg-white/5 px-2 py-0.5 text-xs text-slate-300"
                  onClick={(event) => {
                    event.preventDefault();
                    toggleTag(name);
                  }}
                >
                  {name}
                </span>
              ))}
            </div>
            <p className="mt-3 text-xs text-slate-500">
              {model.asset_count} files · {formatBytes(model.byte_size)}
              {model.uploaded_by ? ` · uploaded by ${model.uploaded_by.display_name}` : ""}
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
