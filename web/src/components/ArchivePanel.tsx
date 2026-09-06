import { useCallback, useEffect, useMemo, useState } from "react";
import {
  api,
  fetchMemberPreview,
  isAbortError,
  memberPreviewUrl,
  type ArchiveMember,
  type ArchiveSummary,
  type Asset
} from "../api";
import {
  ARCHIVE_STREAM_COPY,
  captionForMember,
  displayCaption,
  folderSegments,
  memberKind,
  packFilename,
  prefixThrough,
  type ArchiveView
} from "../archives";
import { formatBytes } from "../format";
import { CalmChip } from "./CalmChip";
import { InlineError, Pulse } from "./UiStates";

type Props = {
  modelId: number;
  modelTitle: string;
  assets: Asset[];
  onOpenMember: (member: ArchiveMember, packName: string) => void;
};

type FolderState = {
  loading: boolean;
  error: string | null;
  children: ArchiveMember[] | null;
};

type Focus = {
  assetId: number;
  prefix: string;
};

export function ArchivePanel({ modelId, modelTitle, assets, onOpenMember }: Props) {
  const archives = useMemo(() => assets.filter((asset) => asset.archive), [assets]);
  const [view, setView] = useState<ArchiveView>("tree");
  const [query, setQuery] = useState("");
  const [debounced, setDebounced] = useState("");
  const [summaries, setSummaries] = useState<ArchiveSummary[]>([]);
  const [openArchives, setOpenArchives] = useState<Record<number, boolean>>({});
  const [folders, setFolders] = useState<Record<string, FolderState>>({});
  const [focus, setFocus] = useState<Focus | null>(null);
  const [flatRows, setFlatRows] = useState<ArchiveMember[] | null>(null);
  const [flatLoading, setFlatLoading] = useState(false);
  const [flatError, setFlatError] = useState<string | null>(null);
  const [searching, setSearching] = useState(false);
  const [searchError, setSearchError] = useState<string | null>(null);
  const [hits, setHits] = useState<ArchiveMember[] | null>(null);

  useEffect(() => {
    const handle = window.setTimeout(() => setDebounced(query.trim()), 220);
    return () => window.clearTimeout(handle);
  }, [query]);

  const loadFolder = useCallback(
    async (assetId: number, prefix: string, signal?: AbortSignal) => {
      const key = `${assetId}:${prefix}`;
      setFolders((current) => ({
        ...current,
        [key]: { loading: true, error: null, children: current[key]?.children ?? null }
      }));
      try {
        const payload = await api.archiveMembers(modelId, {
          asset_id: assetId,
          prefix,
          view: "tree",
          signal
        });
        if (signal?.aborted) return;
        setSummaries(payload.archives);
        setFolders((current) => ({
          ...current,
          [key]: { loading: false, error: null, children: payload.nodes }
        }));
      } catch (err) {
        if (isAbortError(err) || signal?.aborted) return;
        setFolders((current) => ({
          ...current,
          [key]: {
            loading: false,
            error: err instanceof Error ? err.message : "Could not load folder",
            children: current[key]?.children ?? null
          }
        }));
      }
    },
    [modelId]
  );

  const loadFlat = useCallback(
    async (signal?: AbortSignal) => {
      setFlatLoading(true);
      setFlatError(null);
      try {
        const rows: ArchiveMember[] = [];
        let offset = 0;
        let next: number | null = 0;
        while (next != null) {
          const payload = await api.archiveMembers(modelId, {
            view: "flat",
            asset_id: focus?.assetId,
            limit: 200,
            offset,
            signal
          });
          if (signal?.aborted) return;
          setSummaries(payload.archives);
          rows.push(...payload.members);
          next = payload.next_offset;
          offset = payload.next_offset ?? offset;
          if (payload.members.length === 0) break;
        }
        setFlatRows(rows);
      } catch (err) {
        if (isAbortError(err) || signal?.aborted) return;
        setFlatError(err instanceof Error ? err.message : "Could not load archive");
      } finally {
        if (!signal?.aborted) setFlatLoading(false);
      }
    },
    [focus?.assetId, modelId]
  );

  useEffect(() => {
    if (!debounced) {
      setHits(null);
      setSearchError(null);
      setSearching(false);
      return;
    }
    const abort = new AbortController();
    setSearching(true);
    setSearchError(null);
    api
      .archiveMembers(modelId, { q: debounced, limit: 80, signal: abort.signal })
      .then((payload) => {
        setHits(payload.members);
        setSummaries(payload.archives);
      })
      .catch((err) => {
        if (!isAbortError(err)) setSearchError(err instanceof Error ? err.message : "Search failed");
      })
      .finally(() => {
        if (!abort.signal.aborted) setSearching(false);
      });
    return () => abort.abort();
  }, [debounced, modelId]);

  useEffect(() => {
    if (debounced || view !== "flat") return;
    const abort = new AbortController();
    void loadFlat(abort.signal);
    return () => abort.abort();
  }, [debounced, loadFlat, view]);

  useEffect(() => {
    if (archives.length !== 1) return;
    const only = archives[0];
    setOpenArchives((current) => (current[only.id] ? current : { ...current, [only.id]: true }));
    setFocus((current) => current ?? { assetId: only.id, prefix: "" });
    void loadFolder(only.id, "");
  }, [archives, loadFolder]);

  function toggleArchive(assetId: number) {
    setOpenArchives((current) => {
      const next = { ...current, [assetId]: !current[assetId] };
      if (next[assetId] && !folders[`${assetId}:`]) void loadFolder(assetId, "");
      return next;
    });
    setFocus({ assetId, prefix: "" });
  }

  function toggleFolder(assetId: number, node: ArchiveMember) {
    const key = `${assetId}:${node.path}`;
    setFocus({ assetId, prefix: node.path });
    if (folders[key]?.children) {
      setFolders((current) => {
        const copy = { ...current };
        delete copy[key];
        return copy;
      });
      return;
    }
    void loadFolder(assetId, node.path);
  }

  function openMember(member: ArchiveMember) {
    if (member.directory || !member.streamable) return;
    onOpenMember(member, packFilename(member.asset_id, summaries, archives));
  }

  function goBreadcrumb(next: Focus | null) {
    setFocus(next);
    if (next) {
      setOpenArchives((current) => ({ ...current, [next.assetId]: true }));
      if (!folders[`${next.assetId}:${next.prefix}`]) void loadFolder(next.assetId, next.prefix);
    }
  }

  if (archives.length === 0) {
    return (
      <section className="rounded-2xl border border-white/10 bg-ink-900/70 p-4">
        <h2 className="font-display text-xl">Archive</h2>
        <p className="mt-3 text-sm text-slate-500">This model has no zip/3mf/7z/rar files.</p>
      </section>
    );
  }

  const focusedPack = focus ? packFilename(focus.assetId, summaries, archives) : null;
  const crumbs = focus ? folderSegments(focus.prefix) : [];

  return (
    <section className="rounded-2xl border border-white/10 bg-ink-900/70 p-4">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h2 className="font-display text-xl">Archive</h2>
          <p className="mt-1 text-xs text-slate-500">{ARCHIVE_STREAM_COPY}</p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <CalmChip active={view === "tree"} onClick={() => setView("tree")}>
            Tree
          </CalmChip>
          <CalmChip active={view === "flat"} onClick={() => setView("flat")}>
            Flat
          </CalmChip>
          <input
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="Search within pack…"
            className="w-full max-w-xs rounded-full border border-white/10 bg-ink-950 px-4 py-2 text-sm outline-none ring-accent-500 focus:ring-2"
          />
        </div>
      </div>

      <nav className="mt-4 flex flex-wrap items-center gap-1 text-xs text-slate-400" aria-label="Archive path">
        <button type="button" className="hover:text-slate-200" onClick={() => goBreadcrumb(null)}>
          {modelTitle}
        </button>
        {focusedPack ? (
          <>
            <span className="text-slate-600">→</span>
            <button
              type="button"
              className="font-mono text-slate-300 hover:text-white"
              onClick={() => focus && goBreadcrumb({ assetId: focus.assetId, prefix: "" })}
            >
              {focusedPack}
            </button>
          </>
        ) : null}
        {crumbs.map((segment, index) => (
          <span key={`${segment}-${index}`} className="contents">
            <span className="text-slate-600">→</span>
            <button
              type="button"
              className="font-mono text-slate-300 hover:text-white"
              onClick={() => focus && goBreadcrumb({ assetId: focus.assetId, prefix: prefixThrough(crumbs, index) })}
            >
              {segment}
            </button>
          </span>
        ))}
      </nav>

      {debounced ? (
        <SearchList
          query={debounced}
          loading={searching}
          error={searchError}
          hits={hits}
          summaries={summaries}
          assets={archives}
          onRetry={() => {
            setDebounced("");
            window.setTimeout(() => setDebounced(query.trim()), 0);
          }}
          onOpen={openMember}
        />
      ) : view === "flat" ? (
        <FlatList
          loading={flatLoading}
          error={flatError}
          rows={flatRows}
          summaries={summaries}
          assets={archives}
          onRetry={() => void loadFlat()}
          onOpen={openMember}
        />
      ) : (
        <ul className="mt-4 space-y-2">
          {archives.map((asset) => {
            const summary = summaries.find((item) => item.asset_id === asset.id);
            const open = Boolean(openArchives[asset.id]);
            const root = folders[`${asset.id}:`];
            return (
              <li key={asset.id} className="rounded-xl border border-white/5 bg-ink-950/50">
                <button
                  type="button"
                  onClick={() => toggleArchive(asset.id)}
                  className="flex w-full items-center justify-between gap-3 px-3 py-2 text-left text-sm"
                >
                  <span className="text-slate-100">
                    {open ? "▾" : "▸"} {asset.filename}
                  </span>
                  <span className="text-xs text-slate-500">
                    {asset.kind} · {asset.archive_member_count} members
                    {asset.archive_truncated ? " · truncated" : ""}
                    {summary?.support === "placeholder" ? " · listing pending" : ""}
                  </span>
                </button>
                {open ? (
                  <div className="border-t border-white/5 px-2 py-2">
                    {root?.loading && !root.children ? <FolderSkeleton /> : null}
                    {root?.error ? (
                      <div className="px-2 py-1">
                        <InlineError message={root.error} onRetry={() => void loadFolder(asset.id, "")} />
                      </div>
                    ) : null}
                    {root?.children?.length === 0 ? (
                      <p className="px-2 text-sm text-slate-500">Empty folder</p>
                    ) : null}
                    <FolderList
                      assetId={asset.id}
                      prefix=""
                      folders={folders}
                      summaries={summaries}
                      assets={archives}
                      onToggle={toggleFolder}
                      onOpen={openMember}
                      onRetry={loadFolder}
                    />
                  </div>
                ) : null}
              </li>
            );
          })}
        </ul>
      )}
    </section>
  );
}

function SearchList({
  query,
  loading,
  error,
  hits,
  summaries,
  assets,
  onRetry,
  onOpen
}: {
  query: string;
  loading: boolean;
  error: string | null;
  hits: ArchiveMember[] | null;
  summaries: ArchiveSummary[];
  assets: Asset[];
  onRetry: () => void;
  onOpen: (member: ArchiveMember) => void;
}) {
  return (
    <div className="mt-4">
      {loading && !hits ? <FolderSkeleton /> : null}
      {error ? <InlineError message={error} onRetry={onRetry} /> : null}
      {!loading && hits && hits.length === 0 ? (
        <p className="text-sm text-slate-500">No members match “{query}”.</p>
      ) : null}
      <ul className="mt-2 space-y-1">
        {(hits || []).map((member) => (
          <li key={`${member.asset_id}:${member.internal_path}`}>
            <MemberRow member={member} summaries={summaries} assets={assets} onOpen={() => onOpen(member)} />
          </li>
        ))}
      </ul>
    </div>
  );
}

function FlatList({
  loading,
  error,
  rows,
  summaries,
  assets,
  onRetry,
  onOpen
}: {
  loading: boolean;
  error: string | null;
  rows: ArchiveMember[] | null;
  summaries: ArchiveSummary[];
  assets: Asset[];
  onRetry: () => void;
  onOpen: (member: ArchiveMember) => void;
}) {
  return (
    <div className="mt-4">
      {loading && !rows ? <FolderSkeleton rows={8} /> : null}
      {error ? <InlineError message={error} onRetry={onRetry} /> : null}
      {!loading && rows && rows.length === 0 ? <p className="text-sm text-slate-500">Empty folder</p> : null}
      <ul className="space-y-1">
        {(rows || [])
          .filter((member) => !member.directory)
          .map((member) => (
            <li key={`${member.asset_id}:${member.internal_path}`}>
              <MemberRow member={member} summaries={summaries} assets={assets} onOpen={() => onOpen(member)} />
            </li>
          ))}
      </ul>
    </div>
  );
}

function FolderList({
  assetId,
  prefix,
  folders,
  summaries,
  assets,
  onToggle,
  onOpen,
  onRetry,
  depth = 0
}: {
  assetId: number;
  prefix: string;
  folders: Record<string, FolderState>;
  summaries: ArchiveSummary[];
  assets: Asset[];
  onToggle: (assetId: number, node: ArchiveMember) => void;
  onOpen: (member: ArchiveMember) => void;
  onRetry: (assetId: number, prefix: string) => Promise<void>;
  depth?: number;
}) {
  const state = folders[`${assetId}:${prefix}`];
  if (!state?.children) return null;

  return (
    <ul className="space-y-0.5">
      {state.children.map((node) => {
        const childKey = `${assetId}:${node.path}`;
        const child = folders[childKey];
        const expanded = Boolean(child);
        return (
          <li key={node.internal_path}>
            <MemberRow
              member={node}
              summaries={summaries}
              assets={assets}
              depth={depth}
              expanded={expanded}
              onOpen={() => {
                if (node.directory) onToggle(assetId, node);
                else onOpen(node);
              }}
            />
            {node.directory && expanded && child ? (
              <div className="ml-4">
                {child.loading && !child.children ? <FolderSkeleton rows={3} /> : null}
                {child.error ? (
                  <div className="px-2 py-1">
                    <InlineError message={child.error} onRetry={() => void onRetry(assetId, node.path)} />
                  </div>
                ) : null}
                {child.children?.length === 0 ? <p className="px-2 py-1 text-xs text-slate-500">Empty folder</p> : null}
                <FolderList
                  assetId={assetId}
                  prefix={node.path}
                  folders={folders}
                  summaries={summaries}
                  assets={assets}
                  onToggle={onToggle}
                  onOpen={onOpen}
                  onRetry={onRetry}
                  depth={depth + 1}
                />
              </div>
            ) : null}
          </li>
        );
      })}
    </ul>
  );
}

function MemberRow({
  member,
  summaries,
  assets,
  depth = 0,
  expanded,
  onOpen
}: {
  member: ArchiveMember;
  summaries: ArchiveSummary[];
  assets: Asset[];
  depth?: number;
  expanded?: boolean;
  onOpen: () => void;
}) {
  const kind = memberKind(member);
  const muted = !member.directory && !member.streamable;
  const caption = captionForMember(member, summaries, assets);
  const canOpen = member.directory || member.streamable;

  return (
    <div
      className={`flex items-center gap-2 rounded-lg px-2 py-1.5 text-xs ${
        muted ? "text-slate-500" : "hover:bg-white/5"
      }`}
      style={{ paddingLeft: `${0.5 + depth * 0.75}rem` }}
    >
      <button
        type="button"
        disabled={!canOpen}
        onClick={onOpen}
        className={`min-w-0 flex-1 text-left ${canOpen ? "text-slate-200" : "cursor-default text-slate-500"}`}
      >
        <span className="block truncate">
          {member.directory ? (expanded ? "▾ " : "▸ ") : ""}
          {member.name || member.internal_path}
        </span>
        {!member.directory ? (
          <span className="mt-0.5 block font-mono text-[11px] text-slate-500" title={caption}>
            {displayCaption(caption)}
          </span>
        ) : null}
      </button>
      {member.has_preview && member.image && member.id ? (
        <ArchiveThumb url={memberPreviewUrl(member) || api.archiveMemberPreviewUrl(member.id)} />
      ) : null}
      <span className="shrink-0 text-slate-500">
        {member.directory ? `${member.child_count ?? 0} items` : formatBytes(member.uncompressed_size)}
      </span>
      {!member.directory ? <KindPill kind={kind} /> : null}
      {member.streamable && !member.directory ? (
        <button type="button" className="shrink-0 text-accent-400" onClick={onOpen}>
          Open
        </button>
      ) : null}
    </div>
  );
}

function KindPill({ kind }: { kind: ReturnType<typeof memberKind> }) {
  return (
    <span className="inline-flex shrink-0 rounded-full border border-white/10 px-1.5 py-0.5 text-[10px] uppercase tracking-wide text-slate-400">
      {kind}
    </span>
  );
}

function FolderSkeleton({ rows = 5 }: { rows?: number }) {
  return (
    <div className="space-y-2 px-2 py-1" aria-hidden>
      {Array.from({ length: rows }, (_, index) => (
        <Pulse key={index} className="h-8 w-full rounded-lg" />
      ))}
    </div>
  );
}

function ArchiveThumb({ url }: { url: string }) {
  const [src, setSrc] = useState<string | null>(null);

  useEffect(() => {
    let objectUrl: string | null = null;
    let cancelled = false;
    const abort = new AbortController();
    fetchMemberPreview(url, { signal: abort.signal })
      .then((blob) => {
        if (cancelled) return;
        objectUrl = URL.createObjectURL(blob);
        setSrc(objectUrl);
      })
      .catch(() => undefined);
    return () => {
      cancelled = true;
      abort.abort();
      if (objectUrl) URL.revokeObjectURL(objectUrl);
    };
  }, [url]);

  if (!src) return <span className="h-6 w-6 shrink-0 rounded bg-white/5" />;
  return <img src={src} alt="" className="h-6 w-6 shrink-0 rounded object-cover" />;
}
