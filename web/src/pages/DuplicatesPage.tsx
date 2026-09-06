import { useEffect, useMemo, useRef, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { api, type DuplicateGroup, type DuplicateStatus, type ExtractedArchiveAsset, type LibraryInfo } from "../api";
import { useAuth } from "../auth";
import { CalmChip } from "../components/CalmChip";
import { CoverMedia } from "../components/CoverMedia";
import { ConfidenceBadge, DuplicateReview, DuplicateReviewSkeleton, ResidencePill, StatusChip } from "../components/DuplicateReview";
import { EmptyState, InlineError, Pulse } from "../components/UiStates";
import {
  allMembersMergeable,
  applyExtractedMembers,
  archiveMemberIds,
  CONFIDENCE_COPY,
  EXTRACTING_COPY,
  GEOMETRY_ARCHIVE_LEGEND,
  MERGE_UNSUPPORTED_COPY,
  formatWhen,
  groupHasArchive,
  groupMembers,
  isMergeUnsupported,
  newestGroupTime,
  previewModels,
  readLastRun,
  STATUS_FILTERS,
  type StatusFilter,
  writeLastRun
} from "../duplicates";

function GroupRowSkeleton() {
  return (
    <li className="rounded-2xl border border-white/10 bg-ink-900/70 p-4" aria-hidden>
      <div className="flex gap-2">
        <Pulse className="h-5 w-16 rounded-full" />
        <Pulse className="h-5 w-20 rounded-full" />
      </div>
      <div className="mt-4 flex gap-2">
        <Pulse className="h-16 w-16" />
        <Pulse className="h-16 w-16" />
        <Pulse className="h-16 w-16" />
      </div>
    </li>
  );
}

export function DuplicatesPage() {
  const { id } = useParams();
  const navigate = useNavigate();
  const { user } = useAuth();
  const reviewId = id ? Number(id) : null;
  const reviewOpen = Number.isFinite(reviewId);

  const [libraries, setLibraries] = useState<LibraryInfo[]>([]);
  const [libraryId, setLibraryId] = useState<number | "">("");
  const [filter, setFilter] = useState<StatusFilter>("open");
  const [groups, setGroups] = useState<DuplicateGroup[]>([]);
  const [reviewGroup, setReviewGroup] = useState<DuplicateGroup | null>(null);
  const [lastRunAt, setLastRunAt] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [reviewLoading, setReviewLoading] = useState(false);
  const [analyzing, setAnalyzing] = useState(false);
  const [acting, setActing] = useState(false);
  const [busyLabel, setBusyLabel] = useState<string | null>(null);
  const [extractedRows, setExtractedRows] = useState<ExtractedArchiveAsset[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [reviewError, setReviewError] = useState<string | null>(null);
  const analyzeTicket = useRef(0);
  const mounted = useRef(true);

  const selectedLibrary = libraries.find((library) => library.id === libraryId);
  const canReview = Boolean(
    selectedLibrary
      ? (selectedLibrary.can_merge ?? user?.can_merge ?? user?.can_curate)
      : user?.can_merge || user?.can_curate
  );

  useEffect(() => {
    mounted.current = true;
    return () => {
      mounted.current = false;
    };
  }, []);

  useEffect(() => {
    api
      .libraries()
      .then((payload) => {
        if (!mounted.current) return;
        setLibraries(payload.libraries);
        if (payload.libraries[0]) setLibraryId(payload.libraries[0].id);
      })
      .catch((err) => {
        if (!mounted.current) return;
        setError(err instanceof Error ? err.message : "Failed to load libraries");
        setLoading(false);
      });
  }, []);

  async function refresh(options: { silent?: boolean } = {}): Promise<DuplicateGroup[] | null> {
    if (libraryId === "") return null;
    if (!options.silent) {
      setError(null);
      setLoading(true);
    }
    try {
      const status = filter === "all" ? "" : (filter as DuplicateStatus);
      const payload = await api.duplicates(libraryId, status);
      if (!mounted.current) return payload.groups;
      setGroups(payload.groups);
      const stored = readLastRun(libraryId);
      const newest = newestGroupTime(payload.groups);
      setLastRunAt((current) => newest || stored || current);
      if (!options.silent) setError(null);
      return payload.groups;
    } catch (err) {
      if (mounted.current && !options.silent) {
        setError(err instanceof Error ? err.message : "Failed to load duplicates");
      }
      return null;
    } finally {
      if (mounted.current && !options.silent) setLoading(false);
    }
  }

  useEffect(() => {
    if (libraryId === "") return;
    setLastRunAt(readLastRun(libraryId));
    void refresh();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [libraryId, filter]);

  useEffect(() => {
    setExtractedRows([]);
  }, [reviewId]);

  useEffect(() => {
    if (libraryId === "" || !reviewOpen || reviewId == null) {
      setReviewGroup(null);
      setReviewError(null);
      setReviewLoading(false);
      return;
    }
    const fromList = groups.find((group) => group.id === reviewId);
    if (fromList) {
      setReviewGroup(fromList);
      setReviewLoading(false);
      setReviewError(null);
      return;
    }
    let cancelled = false;
    setReviewLoading(true);
    setReviewError(null);
    api
      .duplicates(libraryId)
      .then((payload) => {
        if (cancelled) return;
        const found = payload.groups.find((group) => group.id === reviewId) || null;
        setReviewGroup(found);
        if (!found) setReviewError("This group is not in the library index.");
      })
      .catch((err) => {
        if (cancelled) return;
        setReviewError(err instanceof Error ? err.message : "Failed to load group");
      })
      .finally(() => {
        if (!cancelled) setReviewLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [libraryId, reviewId, reviewOpen, groups]);

  useEffect(() => {
    if (!reviewOpen) return;
    function onKey(event: KeyboardEvent) {
      if (event.key === "Escape") navigate("/duplicates");
    }
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [reviewOpen, navigate]);

  async function analyze() {
    if (libraryId === "" || !canReview || analyzing) return;
    const ticket = ++analyzeTicket.current;
    setAnalyzing(true);
    setError(null);
    try {
      await api.analyzeDuplicates(libraryId);
      const queuedAt = new Date().toISOString();
      writeLastRun(libraryId, queuedAt);
      if (mounted.current) setLastRunAt(queuedAt);
      const priorStamp = newestGroupTime(groups);
      const priorCount = groups.length;
      const started = Date.now();
      while (Date.now() - started < 12000 && analyzeTicket.current === ticket && mounted.current) {
        await new Promise((resolve) => window.setTimeout(resolve, 800));
        if (analyzeTicket.current !== ticket || !mounted.current) return;
        const next = await refresh({ silent: true });
        if (!next) continue;
        const stamp = newestGroupTime(next);
        if (next.length !== priorCount || (stamp && stamp !== priorStamp)) break;
      }
    } catch (err) {
      if (mounted.current) setError(err instanceof Error ? err.message : "Analyze failed");
    } finally {
      if (analyzeTicket.current === ticket && mounted.current) {
        setAnalyzing(false);
        await refresh({ silent: true });
      }
    }
  }

  function closeReview() {
    navigate("/duplicates");
  }

  const displayReviewGroup = useMemo(
    () => (reviewGroup ? applyExtractedMembers(reviewGroup, extractedRows) : null),
    [reviewGroup, extractedRows]
  );

  async function afterDecision(group: DuplicateGroup) {
    setReviewGroup(group);
    if (group.status !== "open") setExtractedRows([]);
    await refresh({ silent: true });
    if (filter === "open" && group.status !== "open") {
      navigate("/duplicates");
    }
  }

  async function keepGroup(group: DuplicateGroup) {
    if (!canReview || acting) return;
    setActing(true);
    setBusyLabel(null);
    setReviewError(null);
    try {
      const payload = await api.keepDuplicate(group.id);
      await afterDecision(payload.group);
    } catch (err) {
      setReviewError(err instanceof Error ? err.message : "Keep failed");
    } finally {
      setActing(false);
    }
  }

  async function dismissGroup(group: DuplicateGroup) {
    if (!canReview || acting) return;
    setActing(true);
    setBusyLabel(null);
    setReviewError(null);
    try {
      const payload = await api.dismissDuplicate(group.id);
      await afterDecision(payload.group);
    } catch (err) {
      setReviewError(err instanceof Error ? err.message : "Dismiss failed");
    } finally {
      setActing(false);
    }
  }

  async function mergeGroup(
    group: DuplicateGroup,
    body: { source_ids: number[]; asset_ids?: number[]; target_id: number; title?: string }
  ) {
    if (!canReview || acting) return;
    if (!allMembersMergeable(group)) {
      setReviewError(MERGE_UNSUPPORTED_COPY);
      return;
    }
    setActing(true);
    setBusyLabel("Merging…");
    setReviewError(null);
    try {
      const payload = await api.mergeDuplicate(group.id, body);
      await afterDecision(payload.group);
    } catch (err) {
      setReviewError(isMergeUnsupported(err) ? MERGE_UNSUPPORTED_COPY : err instanceof Error ? err.message : "Merge failed");
    } finally {
      setActing(false);
      setBusyLabel(null);
    }
  }

  async function extractGroup(
    group: DuplicateGroup,
    body: { archive_member_ids: number[]; target_id?: number; title?: string }
  ) {
    if (!canReview || acting) return;
    setActing(true);
    setBusyLabel(EXTRACTING_COPY);
    setReviewError(null);
    try {
      const payload = await api.extractDuplicate(group.id, {
        archive_member_ids: body.archive_member_ids.length ? body.archive_member_ids : archiveMemberIds(group),
        target_id: body.target_id,
        title: body.title
      });
      setExtractedRows(payload.extracted || payload.assets || []);
      if (payload.group) setReviewGroup(payload.group);
      await refresh({ silent: true });
    } catch (err) {
      setReviewError(err instanceof Error ? err.message : "Extract failed");
    } finally {
      setActing(false);
      setBusyLabel(null);
    }
  }

  async function extractAndMergeGroup(
    group: DuplicateGroup,
    body: { archive_member_ids: number[]; asset_ids: number[]; target_id?: number; title?: string }
  ) {
    if (!canReview || acting) return;
    setActing(true);
    setBusyLabel(EXTRACTING_COPY);
    setReviewError(null);
    try {
      const payload = await api.extractAndMergeDuplicate(group.id, {
        archive_member_ids: body.archive_member_ids.length ? body.archive_member_ids : archiveMemberIds(group),
        asset_ids: body.asset_ids,
        target_id: body.target_id,
        title: body.title
      });
      if (payload.group) {
        await afterDecision(payload.group);
      } else {
        await refresh({ silent: true });
      }
    } catch (err) {
      setReviewError(err instanceof Error ? err.message : "Extract & merge failed");
    } finally {
      setActing(false);
      setBusyLabel(null);
    }
  }

  const lastRunLabel = useMemo(() => {
    const when = formatWhen(lastRunAt);
    if (analyzing) return when ? `Analyzing… last run ${when}` : "Analyzing…";
    if (when) return `Last run ${when}`;
    return "Empty until Analyze. Nothing is deleted from disk automatically.";
  }, [analyzing, lastRunAt]);

  const emptyCopy =
    filter === "open"
      ? "No open duplicates. Run Analyze after a scan if you expect more."
      : "Nothing in this filter.";

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 className="font-display text-3xl text-white">Duplicates</h1>
          <p className="mt-2 max-w-2xl text-sm text-slate-400">
            Review likely copies. Nothing is deleted from disk unless you merge and choose to — and merge never
            silent-deletes.
          </p>
        </div>
        {canReview ? (
          <div className="text-right">
            <button
              type="button"
              disabled={analyzing || libraryId === ""}
              onClick={() => void analyze()}
              className="rounded-lg bg-accent-500 px-3 py-1.5 text-sm text-ink-950 disabled:opacity-60"
            >
              {analyzing ? "Analyzing…" : "Analyze"}
            </button>
            <p className="mt-1 max-w-xs text-xs text-slate-500">{lastRunLabel}</p>
          </div>
        ) : (
          <p className="max-w-xs text-xs text-slate-500">{lastRunLabel}</p>
        )}
      </div>

      <div className="flex flex-wrap items-center gap-3">
        {libraries.length > 1 ? (
          <label className="text-sm text-slate-300">
            Library
            <select
              className="ml-2 rounded-lg border border-white/10 bg-ink-950 px-3 py-1.5"
              value={libraryId}
              onChange={(event) => setLibraryId(Number(event.target.value))}
            >
              {libraries.map((library) => (
                <option key={library.id} value={library.id}>
                  {library.name}
                </option>
              ))}
            </select>
          </label>
        ) : null}
        <div className="flex flex-wrap gap-2">
          {STATUS_FILTERS.map((item) => (
            <CalmChip key={item.id} active={filter === item.id} onClick={() => setFilter(item.id)}>
              {item.label}
            </CalmChip>
          ))}
        </div>
      </div>

      <div>
        <div className="flex flex-wrap gap-2">
          {Object.entries(CONFIDENCE_COPY).map(([key, meta]) => (
            <span
              key={key}
              title={`${meta.hint} · ${key === "exact" ? "content hash" : key === "geometry" ? "geometry digest" : "name and size"}`}
              className="rounded-full border border-white/10 px-2.5 py-1 text-[11px] uppercase tracking-wide text-slate-400"
            >
              {meta.label}
            </span>
          ))}
        </div>
        <p className="mt-2 text-xs text-slate-500">{GEOMETRY_ARCHIVE_LEGEND}</p>
      </div>

      {error ? <InlineError message={error} onRetry={() => void refresh()} /> : null}

      <section aria-busy={loading}>
        {loading ? (
          <ul className="space-y-3">
            <GroupRowSkeleton />
            <GroupRowSkeleton />
            <GroupRowSkeleton />
          </ul>
        ) : (
          <ul className="space-y-3">
            {groups.map((group) => {
              const thumbs = previewModels(group);
              const members = groupMembers(group);
              return (
                <li key={group.id}>
                  <button
                    type="button"
                    onClick={() => navigate(`/duplicates/${group.id}`)}
                    className="flex w-full flex-col rounded-2xl border border-white/10 bg-ink-900/70 p-4 text-left transition hover:border-accent-500/30"
                  >
                    <div className="flex flex-wrap items-center gap-2">
                      <ConfidenceBadge confidence={group.confidence} reason={group.reason} />
                      <span className="text-xs text-slate-500">
                        {members.length} {members.length === 1 ? "member" : "members"}
                      </span>
                      {groupHasArchive(group) ? <ResidencePill archive size="sm" /> : null}
                      <StatusChip status={group.status} />
                    </div>
                    <div className="mt-3 flex gap-2">
                      {thumbs.map((model, index) => (
                        <div key={`${group.id}-thumb-${index}`} className="h-16 w-16 overflow-hidden rounded-lg bg-ink-950">
                          {model ? <CoverMedia model={model} /> : <div className="cover-checker h-full w-full" />}
                        </div>
                      ))}
                    </div>
                    <p className="mt-3 truncate text-sm text-slate-200">{group.filename || "Untitled group"}</p>
                  </button>
                </li>
              );
            })}
          </ul>
        )}
        {!loading && groups.length === 0 && !error ? <EmptyState copy={emptyCopy} /> : null}
      </section>

      {reviewOpen ? (
        reviewLoading && !reviewGroup ? (
          <div className="fixed inset-0 z-40 flex justify-end bg-ink-950/65 backdrop-blur-sm">
            <aside className="flex h-full w-full max-w-4xl flex-col border-l border-white/10 bg-ink-950 p-5 shadow-2xl">
              <DuplicateReviewSkeleton />
            </aside>
          </div>
        ) : displayReviewGroup ? (
          <DuplicateReview
            group={displayReviewGroup}
            canReview={canReview}
            busy={acting}
            busyLabel={busyLabel}
            error={reviewError}
            onKeep={() => void keepGroup(displayReviewGroup)}
            onDismiss={() => void dismissGroup(displayReviewGroup)}
            onMerge={(payload) => void mergeGroup(displayReviewGroup, payload)}
            onExtract={(payload) => void extractGroup(reviewGroup || displayReviewGroup, payload)}
            onExtractAndMerge={(payload) => void extractAndMergeGroup(reviewGroup || displayReviewGroup, payload)}
            onClose={closeReview}
          />
        ) : reviewError ? (
          <div className="fixed inset-0 z-40 grid place-items-center bg-ink-950/65 px-4">
            <div className="w-full max-w-md rounded-2xl border border-white/10 bg-ink-900 p-5">
              <InlineError message={reviewError} onRetry={() => navigate("/duplicates")} />
            </div>
          </div>
        ) : null
      ) : null}
    </div>
  );
}
