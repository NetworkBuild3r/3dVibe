import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { Link, useParams, useSearchParams } from "react-router-dom";
import { api, type Creator, type ModelCard } from "../api";
import { CreatorHeader } from "../components/CreatorHeader";
import { CreatorListItem } from "../components/CreatorListItem";
import { CreatorPackCard } from "../components/CreatorPackCard";
import { ModelCard as ModelCardView } from "../components/ModelCard";
import { CardGridSkeleton, EmptyState, InlineError, SidebarSkeleton } from "../components/UiStates";
import {
  CREATOR_PAGE_SIZE,
  creatorHref,
  creatorsIndexHref,
  emptyCreatorModelsCopy,
  emptyCreatorsIndexCopy,
  filterCreators,
  isMissingCreatorError,
  missingCreatorCopy
} from "../creators";

export function CreatorsPage() {
  const { slug } = useParams();
  const [params] = useSearchParams();
  const query = (params.get("q") || "").trim();

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
  const listRequestRef = useRef(0);
  const sentinel = useRef<HTMLDivElement | null>(null);

  const filtered = useMemo(() => filterCreators(creators, query), [creators, query]);
  const packHome = Boolean(slug);

  const loadList = useCallback(async () => {
    const ticket = ++listRequestRef.current;
    setListLoading(true);
    setListError(null);
    try {
      const payload = await api.creators();
      if (ticket !== listRequestRef.current) return;
      setCreators(payload.creators);
      setListLoading(false);
      await Promise.all(
        payload.creators.map(async (creator) => {
          try {
            const page = await api.creator(creator.slug, null, 4);
            if (ticket !== listRequestRef.current) return;
            setMosaics((current) => ({ ...current, [creator.slug]: page.models }));
          } catch {
            if (ticket !== listRequestRef.current) return;
            setMosaics((current) => ({ ...current, [creator.slug]: [] }));
          }
        })
      );
    } catch (err) {
      if (ticket !== listRequestRef.current) return;
      setListError(err instanceof Error ? err.message : "Could not load creators");
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
      const page = await api.creator(creatorSlug, reset ? null : cursorRef.current, CREATOR_PAGE_SIZE);
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
      if (isMissingCreatorError(err)) {
        setMissing(true);
        setActive(null);
        setModels([]);
      } else {
        setDetailError(err instanceof Error ? err.message : "Could not load creator");
      }
    } finally {
      if (ticket === requestRef.current) {
        loadingRef.current = false;
        setDetailLoading(false);
      }
    }
  }, []);

  useEffect(() => {
    if (!slug) {
      requestRef.current += 1;
      loadingRef.current = false;
      setActive(null);
      setModels([]);
      setMissing(false);
      setDetailError(null);
      setHasMore(false);
      return;
    }
    void loadModels(slug, true);
  }, [slug, loadModels]);

  useEffect(() => {
    if (!sentinel.current || !slug) return;
    const node = sentinel.current;
    const observer = new IntersectionObserver((entries) => {
      if (entries.some((entry) => entry.isIntersecting)) {
        void loadModels(slug, false);
      }
    });
    observer.observe(node);
    return () => observer.disconnect();
  }, [loadModels, slug, models.length, missing]);

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

  if (!packHome) {
    const empty = emptyCreatorsIndexCopy(query);
    return (
      <div>
        <div className="mb-6 flex flex-wrap items-baseline gap-3">
          <h1 className="font-display text-3xl text-white">Creators</h1>
          {!listLoading && !listError ? (
            <p className="text-sm text-slate-500">
              {filtered.length} creator{filtered.length === 1 ? "" : "s"}
            </p>
          ) : null}
        </div>
        {listError ? (
          <div className="mb-5">
            <InlineError message={listError} onRetry={() => void loadList()} />
          </div>
        ) : null}
        {listLoading ? <CardGridSkeleton /> : null}
        {!listLoading && !listError && filtered.length === 0 ? (
          <EmptyState copy={empty.copy} ctaTo={empty.ctaTo} ctaLabel={empty.ctaLabel} />
        ) : null}
        {!listLoading && filtered.length > 0 ? (
          <div className="card-grid">
            {filtered.map((creator) => (
              <CreatorPackCard
                key={creator.id}
                creator={creator}
                covers={mosaics[creator.slug] || []}
                to={creatorHref(creator.slug, query)}
              />
            ))}
          </div>
        ) : null}
      </div>
    );
  }

  const showDetailSkeleton = detailLoading && models.length === 0 && !missing && !detailError;
  const missingCopy = missingCreatorCopy();
  const emptyModels = slug ? emptyCreatorModelsCopy(slug) : null;

  return (
    <div className="-mx-6 -my-6 flex min-h-[calc(100vh-4.25rem)]">
      <aside className="hidden w-80 shrink-0 flex-col border-r border-white/5 bg-ink-950/40 lg:flex">
        <div className="px-4 pb-2 pt-5">
          <Link to={creatorsIndexHref(query)} className="font-display text-2xl text-white">
            Creators
          </Link>
          <p className="mt-1 text-sm text-slate-500">Pack homes with cover mosaics.</p>
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
              copy={emptyCreatorsIndexCopy(query).copy}
              ctaTo="/creators"
              ctaLabel="All creators"
            />
          ) : null}
          <div className="space-y-2">
            {filtered.map((creator) => (
              <CreatorListItem
                key={creator.id}
                creator={creator}
                covers={mosaics[creator.slug] || []}
                selected={creator.slug === slug}
                to={creatorHref(creator.slug, query)}
              />
            ))}
          </div>
        </div>
      </aside>

      <section className="min-w-0 flex-1 overflow-auto px-6 py-5">
        <Link to={creatorsIndexHref(query)} className="mb-4 inline-block text-sm text-slate-400 hover:text-white">
          All creators
        </Link>
        {missing ? <EmptyState copy={missingCopy.copy} ctaTo={missingCopy.ctaTo} ctaLabel={missingCopy.ctaLabel} /> : null}
        {detailError ? (
          <div className="mb-4">
            <InlineError message={detailError} onRetry={() => slug && void loadModels(slug, true)} />
          </div>
        ) : null}
        {showDetailSkeleton ? (
          <div>
            <div className="mb-6 h-20 animate-pulse rounded-2xl bg-white/5" />
            <CardGridSkeleton />
          </div>
        ) : null}
        {active && !missing ? (
          <>
            <CreatorHeader creator={active} covers={mosaics[active.slug] || models.slice(0, 4)} />
            <div className="mt-6">
              {models.length === 0 && !detailLoading && emptyModels ? (
                <EmptyState copy={emptyModels.copy} ctaTo={emptyModels.ctaTo} ctaLabel={emptyModels.ctaLabel} />
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
      </section>
    </div>
  );
}
