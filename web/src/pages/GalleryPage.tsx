import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useSearchParams } from "react-router-dom";
import { api, type Creator, type ModelCard } from "../api";
import { CalmChip, ChipDropdown, ChipOption } from "../components/CalmChip";
import { ModelCard as ModelCardView } from "../components/ModelCard";
import { CardGridSkeleton, EmptyState, InlineError } from "../components/UiStates";
import { hasReadyCover } from "../covers";

const PAGE_SIZE = 18;
const SEARCH_DEBOUNCE_MS = 280;

function catalogQuery(query: string, tag: string, creatorSlug: string, hasCover: boolean) {
  return Boolean(query.trim() || tag || creatorSlug || hasCover);
}

export function GalleryPage() {
  const [params, setParams] = useSearchParams();
  const query = params.get("q") || "";
  const tag = params.get("tag") || "";
  const creatorSlug = params.get("creator") || "";
  const hasCover = params.get("cover") === "1";

  const [models, setModels] = useState<ModelCard[]>([]);
  const [creators, setCreators] = useState<Creator[]>([]);
  const [hasMore, setHasMore] = useState(true);
  const [loading, setLoading] = useState(false);
  const [status, setStatus] = useState("");
  const [engine, setEngine] = useState("");
  const [estimatedTotal, setEstimatedTotal] = useState<number | null>(null);
  const [libraryTotal, setLibraryTotal] = useState<number | null>(null);
  const [facetTags, setFacetTags] = useState<Record<string, number>>({});
  const [actionError, setActionError] = useState<string | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [likeBusyId, setLikeBusyId] = useState<number | null>(null);
  const sentinel = useRef<HTMLDivElement | null>(null);
  const queryRef = useRef(query);
  const tagRef = useRef(tag);
  const creatorRef = useRef(creatorSlug);
  const coverRef = useRef(hasCover);
  const cursorRef = useRef<string | null>(null);
  const offsetRef = useRef(0);
  const hasMoreRef = useRef(true);
  const loadingRef = useRef(false);
  const requestRef = useRef(0);

  const activeSearch = catalogQuery(query, tag, creatorSlug, hasCover);

  const tagOptions = useMemo(() => {
    const counts = { ...facetTags };
    models.forEach((model) => {
      model.tags.forEach((name) => {
        if (counts[name] == null) counts[name] = 0;
      });
    });
    return Object.entries(counts).sort((a, b) => a[0].localeCompare(b[0]));
  }, [facetTags, models]);

  const visibleModels = useMemo(
    () => (hasCover ? models.filter(hasReadyCover) : models),
    [hasCover, models]
  );

  const creatorOptions = useMemo(() => {
    return [...creators].sort((a, b) => a.name.localeCompare(b.name));
  }, [creators]);

  const selectedCreator = creators.find((item) => item.slug === creatorSlug);

  const patchParams = useCallback(
    (updates: Record<string, string | null>) => {
      const next = new URLSearchParams(params);
      Object.entries(updates).forEach(([key, value]) => {
        if (value) next.set(key, value);
        else next.delete(key);
      });
      setParams(next, { replace: true });
    },
    [params, setParams]
  );

  const loadMore = useCallback(async () => {
    if (loadingRef.current || !hasMoreRef.current) return;
    const q = queryRef.current.trim();
    const selectedTag = tagRef.current;
    const slug = creatorRef.current;
    const coverOnly = coverRef.current;
    const useSearch = catalogQuery(q, selectedTag, slug, coverOnly);
    const ticket = ++requestRef.current;

    loadingRef.current = true;
    setLoading(true);
    setLoadError(null);
    setStatus("Loading more…");
    try {
      if (useSearch) {
        const page = await api.search({
          q,
          tag: selectedTag || undefined,
          creator_slug: slug || undefined,
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
        setEstimatedTotal(page.estimated_total);
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
        setEstimatedTotal(null);
        setStatus(next ? "" : "End of library");
      }
    } catch (err) {
      if (ticket !== requestRef.current) return;
      setLoadError(err instanceof Error ? err.message : "Could not load models");
      setStatus("");
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
    api
      .creators()
      .then((payload) => setCreators(payload.creators))
      .catch(() => undefined);
    api
      .libraries()
      .then((payload) => setLibraryTotal(payload.libraries.reduce((sum, library) => sum + (library.model_count || 0), 0)))
      .catch(() => undefined);
    api
      .search({ limit: 1 })
      .then((page) => setFacetTags(page.facets?.tags || {}))
      .catch(() => undefined);
  }, []);

  useEffect(() => {
    queryRef.current = query;
    tagRef.current = tag;
    creatorRef.current = creatorSlug;
    coverRef.current = hasCover;
    const handle = window.setTimeout(() => {
      resetAndLoad();
    }, SEARCH_DEBOUNCE_MS);
    return () => window.clearTimeout(handle);
  }, [query, tag, creatorSlug, hasCover, resetAndLoad]);

  function clearFilters() {
    patchParams({ tag: null, creator: null, cover: null });
  }

  async function toggleLike(model: ModelCard) {
    if (likeBusyId != null) return;
    setActionError(null);
    setLikeBusyId(model.id);
    try {
      const payload = model.liked ? await api.unlikeModel(model.id) : await api.likeModel(model.id);
      setModels((current) => current.map((item) => (item.id === model.id ? { ...item, ...payload.model } : item)));
    } catch (err) {
      setActionError(err instanceof Error ? err.message : "Could not update like");
    } finally {
      setLikeBusyId(null);
    }
  }

  const headerCount = activeSearch ? estimatedTotal : libraryTotal;
  const showInitialSkeleton = loading && models.length === 0 && !loadError;
  const coverPendingOnly =
    !loading && models.length > 0 && visibleModels.length === 0 && hasCover;

  return (
    <div>
      <div className="mb-5">
        <div className="flex flex-wrap items-baseline gap-3">
          <h1 className="font-display text-3xl text-white">Library</h1>
          {headerCount != null ? (
            <p className="text-sm text-slate-500">
              {headerCount.toLocaleString()} model{headerCount === 1 ? "" : "s"}
            </p>
          ) : null}
        </div>
      </div>

      <div className="mb-6 flex flex-wrap items-center gap-2">
        <CalmChip active={!tag && !creatorSlug && !hasCover} onClick={clearFilters}>
          All
        </CalmChip>
        <ChipDropdown
          label="Creators"
          active={Boolean(creatorSlug)}
          activeLabel={selectedCreator?.name || creatorSlug}
          empty={creatorOptions.length ? undefined : "No creators yet"}
        >
          {creatorOptions.map((item) => (
            <ChipOption
              key={item.slug}
              selected={creatorSlug === item.slug}
              onSelect={() => patchParams({ creator: creatorSlug === item.slug ? null : item.slug })}
            >
              <span>{item.name}</span>
              {item.model_count != null ? <span className="text-xs text-slate-500">{item.model_count}</span> : null}
            </ChipOption>
          ))}
        </ChipDropdown>
        <ChipDropdown
          label="Tags"
          active={Boolean(tag)}
          activeLabel={tag}
          empty={tagOptions.length ? undefined : "No tags yet"}
        >
          {tagOptions.map(([name, count]) => (
            <ChipOption
              key={name}
              selected={tag === name}
              onSelect={() => patchParams({ tag: tag === name ? null : name })}
            >
              <span>{name}</span>
              {count ? <span className="text-xs text-slate-500">{count}</span> : null}
            </ChipOption>
          ))}
        </ChipDropdown>
        <CalmChip active={hasCover} onClick={() => patchParams({ cover: hasCover ? null : "1" })}>
          Has cover
        </CalmChip>
        {activeSearch && engine ? <span className="ml-auto text-xs text-slate-500">{engine}</span> : null}
      </div>

      {actionError ? (
        <div className="mb-5">
          <InlineError message={actionError} />
        </div>
      ) : null}
      {loadError ? (
        <div className="mb-5">
          <InlineError message={loadError} onRetry={() => resetAndLoad()} />
        </div>
      ) : null}

      {showInitialSkeleton ? <CardGridSkeleton /> : null}

      {!showInitialSkeleton && visibleModels.length === 0 && !loadError ? (
        <EmptyState
          copy={
            coverPendingOnly
              ? "No ready covers yet. Unscanned or pending models stay on the checker until Rendering writes back."
              : activeSearch
                ? "No models match these filters."
                : "The library is empty. Scan the NFS mount to index folders."
          }
          ctaTo={coverPendingOnly || activeSearch ? undefined : "/libraries"}
          ctaLabel={coverPendingOnly || activeSearch ? undefined : "Open libraries"}
        />
      ) : null}

      {visibleModels.length > 0 ? (
        <div className="card-grid">
          {visibleModels.map((model) => (
            <ModelCardView
              key={model.id}
              model={model}
              likeBusy={likeBusyId === model.id}
              onLike={(item) => void toggleLike(item)}
              onTag={(name) => patchParams({ tag: tag === name ? null : name })}
            />
          ))}
        </div>
      ) : null}

      <div ref={sentinel} className="h-10" />
      <p className="py-4 text-center text-sm text-slate-500">
        {loading ? "Loading more…" : status || (hasMore ? "" : "End of library")}
      </p>
    </div>
  );
}
