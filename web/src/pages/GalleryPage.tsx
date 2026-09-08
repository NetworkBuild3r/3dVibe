import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useSearchParams } from "react-router-dom";
import { api } from "../api";
import { useLibrary } from "../library";
import type { Creator, LibraryMember, ModelCard } from "../types";
import { GalleryFilterBar } from "../components/GalleryFilterBar";
import { ModelCard as ModelCardView } from "../components/ModelCard";
import { OpsStrip } from "../components/OpsStrip";
import { CardGridSkeleton, EmptyState, InlineError } from "../components/UiStates";
import { VirtualizedCardGrid } from "../components/VirtualizedCardGrid";
import {
  PAGE_SIZE,
  SEARCH_DEBOUNCE_MS,
  catalogQuery,
  emptyLibraryCopy,
  engineStatus,
  filterPacksByCategory,
  galleryFilterClearParams,
  hasActiveFilters,
  headerCountLabel,
  nextGalleryHasMore,
  readDensity,
  readGalleryFilters,
  shouldReloadGalleryForScan,
  usesSearchEndpoint,
  writeDensity,
  type CatalogFacets,
  type GalleryDensity,
  type ScanProgress
} from "../gallery";
import { canToggleCardLike, cardLikeBusy, clearLikeBusy, markLikeBusy } from "../likes";
import { OPS_POLL_MS, isActiveScan, packsIndexedCount, parseOpsPayload } from "../ops";

export function GalleryPage() {
  const [params, setParams] = useSearchParams();
  const filters = useMemo(() => readGalleryFilters(params), [params]);
  const queryKey = `${filters.q}\0${filters.tag}\0${filters.creator}\0${filters.category}\0${filters.hasCover}\0${filters.uploadedBy}`;
  const { libraries, library, refresh: refreshLibraries } = useLibrary();

  const [models, setModels] = useState<ModelCard[]>([]);
  const [creators, setCreators] = useState<Creator[]>([]);
  const [facets, setFacets] = useState<CatalogFacets | undefined>(undefined);
  const [facetsReady, setFacetsReady] = useState(false);
  const [hasMore, setHasMore] = useState(true);
  const [loading, setLoading] = useState(false);
  const [status, setStatus] = useState("");
  const [engine, setEngine] = useState("");
  const [estimatedTotal, setEstimatedTotal] = useState<number | null>(null);
  const [libraryTotal, setLibraryTotal] = useState<number | null>(null);
  const [capped, setCapped] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [likeBusyIds, setLikeBusyIds] = useState<number[]>([]);
  const [density, setDensity] = useState<GalleryDensity>(() => readDensity(window.localStorage));
  const [members, setMembers] = useState<LibraryMember[]>([]);
  const [membersReady, setMembersReady] = useState(false);
  const [membersError, setMembersError] = useState<string | null>(null);

  const sentinel = useRef<HTMLDivElement | null>(null);
  const filtersRef = useRef(filters);
  const cursorRef = useRef<string | null>(null);
  const offsetRef = useRef(0);
  const hasMoreRef = useRef(true);
  const loadingRef = useRef(false);
  const requestRef = useRef(0);
  const membersTicket = useRef(0);
  const likeBusyRef = useRef<number[]>([]);
  const [scanProgress, setScanProgress] = useState<ScanProgress>({ scanning: false, packsIndexed: 0 });
  const scanProgressRef = useRef(scanProgress);

  const activeSearch = hasActiveFilters(filters);

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

  const clearFilters = useCallback(() => {
    patchParams(galleryFilterClearParams());
  }, [patchParams]);

  const applyDensity = useCallback((next: GalleryDensity) => {
    setDensity(next);
    writeDensity(window.localStorage, next);
  }, []);

  const loadMore = useCallback(async () => {
    if (loadingRef.current || !hasMoreRef.current) return;
    const current = filtersRef.current;
    const query = catalogQuery(current);
    const useSearch = usesSearchEndpoint(current);
    const ticket = ++requestRef.current;
    const firstPage = useSearch ? offsetRef.current === 0 : cursorRef.current == null;

    loadingRef.current = true;
    setLoading(true);
    setLoadError(null);
    setStatus("Loading more…");
    try {
      if (useSearch) {
        const page = await api.search({
          ...query,
          uploaded_by: query.uploaded_by,
          offset: offsetRef.current,
          limit: PAGE_SIZE
        });
        if (ticket !== requestRef.current) return;
        setModels((currentModels) => {
          const seen = new Set(currentModels.map((item) => item.id));
          return [...currentModels, ...page.models.filter((item) => !seen.has(item.id))];
        });
        setFacets(page.facets);
        setFacetsReady(true);
        offsetRef.current = page.next_offset ?? offsetRef.current + page.models.length;
        const more = nextGalleryHasMore({ ok: true, hasMore: page.next_offset != null });
        hasMoreRef.current = more;
        setHasMore(more);
        setEstimatedTotal(page.estimated_total);
        setCapped(Boolean(page.capped));
        const label = engineStatus(page.engine, page.fallback, Boolean(page.capped));
        setEngine(label);
        setStatus(
          page.models.length || offsetRef.current
            ? page.next_offset != null
              ? label
              : `${label ? `${label} · ` : ""}${page.estimated_total.toLocaleString()} match${
                  page.estimated_total === 1 ? "" : "es"
                }`
            : "No matches"
        );
      } else {
        const [page, facetPage] = await Promise.all([
          api.models({
            cursor: cursorRef.current,
            limit: PAGE_SIZE,
            creator_slug: query.creator_slug,
            tag: query.tag,
            has_cover: query.has_cover,
            uploaded_by: query.uploaded_by
          }),
          firstPage
            ? api
                .search({
                  creator_slug: query.creator_slug,
                  tag: query.tag,
                  has_cover: query.has_cover,
                  uploaded_by: query.uploaded_by,
                  limit: 1
                })
                .catch(() => null)
            : Promise.resolve(null)
        ]);
        if (ticket !== requestRef.current) return;
        setModels((currentModels) => {
          const seen = new Set(currentModels.map((item) => item.id));
          return [...currentModels, ...page.models.filter((item) => !seen.has(item.id))];
        });
        const next = page.next_cursor ? String(page.next_cursor) : null;
        cursorRef.current = next;
        const more = nextGalleryHasMore({ ok: true, hasMore: Boolean(next) });
        hasMoreRef.current = more;
        setHasMore(more);
        if (facetPage) {
          setFacets(facetPage.facets);
          setFacetsReady(true);
          if (hasActiveFilters(current)) {
            setEstimatedTotal(facetPage.estimated_total);
            setCapped(Boolean(facetPage.capped));
            setEngine(engineStatus(facetPage.engine, facetPage.fallback, Boolean(facetPage.capped)));
          } else {
            setEstimatedTotal(null);
            setCapped(false);
            setEngine("");
          }
        }
        setStatus(next ? "" : "End of library");
      }
    } catch (err) {
      if (ticket !== requestRef.current) return;
      const more = nextGalleryHasMore({ ok: false });
      hasMoreRef.current = more;
      setHasMore(more);
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
  }, []);

  useEffect(() => {
    if (!libraries.length) return;
    setLibraryTotal(libraries.reduce((sum, item) => sum + (item.model_count || 0), 0));
  }, [libraries]);

  const loadMembers = useCallback(() => {
    if (!library) return;
    const ticket = ++membersTicket.current;
    setMembersReady(false);
    setMembersError(null);
    api
      .libraryMembers(library.id)
      .then((payload) => {
        if (ticket !== membersTicket.current) return;
        setMembers(payload.members);
        setMembersReady(true);
      })
      .catch((err) => {
        if (ticket !== membersTicket.current) return;
        setMembers([]);
        setMembersReady(true);
        setMembersError(err instanceof Error ? err.message : "Could not load members");
      });
  }, [library]);

  useEffect(() => {
    loadMembers();
  }, [loadMembers]);

  useEffect(() => {
    filtersRef.current = filters;
    const handle = window.setTimeout(() => {
      resetAndLoad();
    }, SEARCH_DEBOUNCE_MS);
    return () => window.clearTimeout(handle);
  }, [queryKey, filters, resetAndLoad]);

  useEffect(() => {
    let cancelled = false;
    async function tick() {
      try {
        const payload = await api.ops();
        if (cancelled) return;
        const next = parseOpsPayload(payload);
        const progress: ScanProgress = next
          ? { scanning: isActiveScan(next.scan), packsIndexed: packsIndexedCount(next.scan) }
          : { scanning: false, packsIndexed: 0 };
        const prev = scanProgressRef.current;
        const reload = shouldReloadGalleryForScan(prev, progress);
        scanProgressRef.current = progress;
        setScanProgress(progress);
        if (reload) {
          void refreshLibraries().catch(() => undefined);
          resetAndLoad();
        }
      } catch {
        /* ops is curator-gated; gallery still lists packs */
      }
    }
    void tick();
    const timer = window.setInterval(() => {
      if (document.visibilityState === "visible") void tick();
    }, OPS_POLL_MS);
    return () => {
      cancelled = true;
      window.clearInterval(timer);
    };
  }, [refreshLibraries, resetAndLoad]);

  async function toggleLike(model: ModelCard) {
    if (!canToggleCardLike(likeBusyRef.current, model.id)) return;
    likeBusyRef.current = markLikeBusy(likeBusyRef.current, model.id);
    setLikeBusyIds(likeBusyRef.current);
    setActionError(null);
    try {
      const payload = model.liked ? await api.unlikeModel(model.id) : await api.likeModel(model.id);
      setModels((current) => current.map((item) => (item.id === model.id ? { ...item, ...payload.model } : item)));
    } catch (err) {
      setActionError(err instanceof Error ? err.message : "Could not update like");
    } finally {
      likeBusyRef.current = clearLikeBusy(likeBusyRef.current, model.id);
      setLikeBusyIds(likeBusyRef.current);
    }
  }

  const visibleModels = useMemo(
    () => filterPacksByCategory(models, filters.category),
    [models, filters.category]
  );
  const headerCount = activeSearch
    ? estimatedTotal
    : scanProgress.scanning
      ? scanProgress.packsIndexed
      : libraryTotal;
  const countLabel = headerCountLabel({ filtered: activeSearch, count: headerCount, capped: activeSearch && capped });
  const showInitialSkeleton = loading && models.length === 0 && !loadError;
  const empty = emptyLibraryCopy(filters, {
    members,
    scanning: scanProgress.scanning,
    packsIndexed: scanProgress.packsIndexed
  });

  return (
    <div>
      <div className="mb-4 flex flex-wrap items-baseline gap-3">
        <h1 className="font-display text-3xl text-white">Library</h1>
        {countLabel ? <p className="text-sm text-slate-500">{countLabel}</p> : null}
      </div>

      <div className="mb-3 empty:hidden">
        <OpsStrip />
      </div>

      <GalleryFilterBar
        filters={filters}
        facets={facets}
        creators={creators}
        models={models}
        members={members}
        membersReady={membersReady}
        membersError={membersError}
        density={density}
        engine={engine}
        facetsReady={facetsReady}
        loadError={loadError}
        onPatch={patchParams}
        onClear={clearFilters}
        onRetry={() => resetAndLoad()}
        onRetryMembers={loadMembers}
        onDensity={applyDensity}
      />

      {actionError ? (
        <div className="mb-5">
          <InlineError message={actionError} />
        </div>
      ) : null}

      {showInitialSkeleton ? <CardGridSkeleton cards={density === "compact" ? 12 : 8} /> : null}

      {!showInitialSkeleton && visibleModels.length === 0 && !loadError ? (
        <EmptyState
          copy={empty.copy}
          onCta={empty.clearFilters ? clearFilters : undefined}
          ctaTo={empty.clearFilters ? undefined : "/libraries"}
          ctaLabel={empty.clearFilters ? "Clear filters" : "Open libraries"}
        />
      ) : null}

      {visibleModels.length > 0 ? (
        <VirtualizedCardGrid
          key={density}
          models={visibleModels}
          density={density}
          renderCard={(model) => (
            <ModelCardView
              model={model}
              likeBusy={cardLikeBusy(likeBusyIds, model.id)}
              onLike={(item) => void toggleLike(item)}
              onTag={(name) => patchParams({ tag: filters.tag === name ? null : name })}
            />
          )}
        />
      ) : null}

      <div ref={sentinel} className="h-10" />
      <p className="py-4 text-center text-sm text-slate-500">
        {loading ? "Loading more…" : status || (hasMore ? "" : "End of library")}
      </p>
    </div>
  );
}
