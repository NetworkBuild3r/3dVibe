import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useParams, useSearchParams } from "react-router-dom";
import { api, type Creator, type ModelCard } from "../api";
import { CreatorHeader } from "../components/CreatorHeader";
import { CreatorListItem } from "../components/CreatorListItem";
import { ModelCard as ModelCardView } from "../components/ModelCard";
import { CardGridSkeleton, EmptyState, InlineError, SidebarSkeleton } from "../components/UiStates";

const PAGE_SIZE = 24;

export function CreatorsPage() {
  const { slug } = useParams();
  const [params] = useSearchParams();
  const query = (params.get("q") || "").trim().toLowerCase();

  const [creators, setCreators] = useState<Creator[]>([]);
  const [mosaics, setMosaics] = useState<Record<string, ModelCard[]>>({});
  const [listLoading, setListLoading] = useState(true);
  const [listError, setListError] = useState<string | null>(null);

  const [active, setActive] = useState<Creator | null>(null);
  const [models, setModels] = useState<ModelCard[]>([]);
  const [detailLoading, setDetailLoading] = useState(false);
  const [detailError, setDetailError] = useState<string | null>(null);
  const [missing, setMissing] = useState(false);
  const [hasMore, setHasMore] = useState(false);
  const [likeBusyId, setLikeBusyId] = useState<number | null>(null);

  const cursorRef = useRef<string | null>(null);
  const hasMoreRef = useRef(false);
  const loadingRef = useRef(false);
  const requestRef = useRef(0);
  const sentinel = useRef<HTMLDivElement | null>(null);

  const filtered = useMemo(() => {
    if (!query) return creators;
    return creators.filter(
      (creator) => creator.name.toLowerCase().includes(query) || creator.slug.toLowerCase().includes(query)
    );
  }, [creators, query]);

  const selectedSlug = slug || filtered[0]?.slug;

  const loadList = useCallback(async () => {
    setListLoading(true);
    setListError(null);
    try {
      const payload = await api.creators();
      setCreators(payload.creators);
      const covers: Record<string, ModelCard[]> = {};
      await Promise.all(
        payload.creators.map(async (creator) => {
          try {
            const page = await api.creator(creator.slug, null, 4);
            covers[creator.slug] = page.models;
          } catch {
            covers[creator.slug] = [];
          }
        })
      );
      setMosaics(covers);
    } catch (err) {
      setListError(err instanceof Error ? err.message : "Could not load creators");
    } finally {
      setListLoading(false);
    }
  }, []);

  useEffect(() => {
    void loadList();
  }, [loadList]);

  const loadModels = useCallback(async (creatorSlug: string, reset: boolean) => {
    if (!reset && (loadingRef.current || !hasMoreRef.current)) return;
    const ticket = ++requestRef.current;
    loadingRef.current = true;
    setDetailLoading(true);
    setDetailError(null);
    setMissing(false);
    if (reset) {
      cursorRef.current = null;
      hasMoreRef.current = true;
      setModels([]);
      setActive(null);
    }
    try {
      const page = await api.creator(creatorSlug, reset ? null : cursorRef.current, PAGE_SIZE);
      if (ticket !== requestRef.current) return;
      setActive(page.creator);
      setModels((current) => {
        const base = reset ? [] : current;
        const seen = new Set(base.map((item) => item.id));
        return [...base, ...page.models.filter((item) => !seen.has(item.id))];
      });
      setMosaics((current) => ({ ...current, [page.creator.slug]: page.models.slice(0, 4) }));
      const next = page.next_cursor ? String(page.next_cursor) : null;
      cursorRef.current = next;
      hasMoreRef.current = Boolean(next);
      setHasMore(Boolean(next));
    } catch (err) {
      if (ticket !== requestRef.current) return;
      const message = err instanceof Error ? err.message : "Could not load creator";
      if (message === "not_found" || /not_found|404/.test(message)) {
        setMissing(true);
        setActive(null);
        setModels([]);
      } else {
        setDetailError(message);
      }
    } finally {
      if (ticket === requestRef.current) {
        loadingRef.current = false;
        setDetailLoading(false);
      }
    }
  }, []);

  useEffect(() => {
    if (!selectedSlug) {
      setActive(null);
      setModels([]);
      setMissing(Boolean(slug));
      return;
    }
    void loadModels(selectedSlug, true);
  }, [selectedSlug, slug, loadModels]);

  useEffect(() => {
    if (!sentinel.current) return;
    const node = sentinel.current;
    const observer = new IntersectionObserver((entries) => {
      if (entries.some((entry) => entry.isIntersecting) && selectedSlug) {
        void loadModels(selectedSlug, false);
      }
    });
    observer.observe(node);
    return () => observer.disconnect();
  }, [loadModels, selectedSlug]);

  async function toggleLike(model: ModelCard) {
    if (likeBusyId != null) return;
    setLikeBusyId(model.id);
    try {
      const payload = model.liked ? await api.unlikeModel(model.id) : await api.likeModel(model.id);
      setModels((current) => current.map((item) => (item.id === model.id ? { ...item, ...payload.model } : item)));
    } catch {
      setDetailError("Could not update like");
    } finally {
      setLikeBusyId(null);
    }
  }

  const showDetailSkeleton = detailLoading && models.length === 0 && !missing && !detailError;

  return (
    <div className="-mx-6 -my-6 flex min-h-[calc(100vh-4.25rem)]">
      <aside className="flex w-80 shrink-0 flex-col border-r border-white/5 bg-ink-950/40">
        <div className="px-4 pb-2 pt-5">
          <h1 className="font-display text-2xl text-white">Creators</h1>
          <p className="mt-1 text-sm text-slate-500">Discover creators and their models.</p>
        </div>
        <div className="min-h-0 flex-1 overflow-auto px-3 pb-4">
          {listError ? (
            <div className="px-1 py-3">
              <InlineError message={listError} onRetry={() => void loadList()} />
            </div>
          ) : null}
          {listLoading ? <SidebarSkeleton rows={6} /> : null}
          {!listLoading && filtered.length === 0 ? (
            <EmptyState
              copy={query ? "No creators match that search." : "No creators yet. Scan the library to infer names from folders."}
              ctaTo="/"
              ctaLabel="Back to library"
            />
          ) : null}
          <div className="space-y-2">
            {filtered.map((creator) => (
              <CreatorListItem
                key={creator.id}
                creator={creator}
                covers={mosaics[creator.slug] || []}
                selected={creator.slug === selectedSlug}
                to={`/creators/${creator.slug}${query ? `?q=${encodeURIComponent(query)}` : ""}`}
              />
            ))}
          </div>
        </div>
      </aside>

      <section className="min-w-0 flex-1 overflow-auto px-6 py-5">
        {missing ? (
          <EmptyState copy="This creator is missing or has not been scanned yet." ctaTo="/creators" ctaLabel="All creators" />
        ) : null}
        {detailError ? (
          <div className="mb-4">
            <InlineError message={detailError} onRetry={() => selectedSlug && void loadModels(selectedSlug, true)} />
          </div>
        ) : null}
        {showDetailSkeleton ? (
          <div>
            <div className="mb-6 h-28 animate-pulse rounded-2xl bg-white/5" />
            <CardGridSkeleton />
          </div>
        ) : null}
        {active && !missing ? (
          <>
            <CreatorHeader creator={active} />
            <div className="mt-6">
              {models.length === 0 && !detailLoading ? (
                <EmptyState copy="This creator has no models yet." ctaTo="/" ctaLabel="Browse the library" />
              ) : (
                <div className="card-grid">
                  {models.map((model) => (
                    <ModelCardView
                      key={model.id}
                      model={model}
                      likeBusy={likeBusyId === model.id}
                      onLike={(item) => void toggleLike(item)}
                    />
                  ))}
                </div>
              )}
              <div ref={sentinel} className="h-10" />
              <p className="py-3 text-center text-sm text-slate-500">
                {detailLoading ? "Loading models…" : hasMore ? "" : models.length ? "End of creator library" : ""}
              </p>
            </div>
          </>
        ) : null}
        {!selectedSlug && !listLoading && !missing ? (
          <EmptyState copy="Select a creator to see their models." />
        ) : null}
      </section>
    </div>
  );
}
