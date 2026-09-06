import { useCallback, useEffect, useMemo, useState } from "react";
import {
  api,
  fetchAuthedBlob,
  type ArchiveMember,
  type ArchiveSummary,
  type Asset
} from "../api";
import { formatBytes } from "../format";

type Props = {
  modelId: number;
  assets: Asset[];
  onOpenMesh: (member: ArchiveMember) => void;
  onOpenImage: (member: ArchiveMember) => void;
};

type FolderState = {
  loading: boolean;
  error: string | null;
  children: ArchiveMember[] | null;
};

function supportLabel(support: string | null | undefined, kind: string) {
  if (support === "full") return "full listing + stream";
  if (support === "best_effort") return "best-effort 7z listing";
  if (support === "placeholder") return kind === "7z" || kind === "rar" ? "7z/rar listing pending" : "listing pending";
  return support || "indexed";
}

async function downloadMember(member: ArchiveMember) {
  if (!member.id) return;
  const blob = await fetchAuthedBlob(api.archiveMemberContentUrl(member.id, true));
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = member.name || "archive-member";
  link.click();
  URL.revokeObjectURL(url);
}

export function ArchivePanel({ modelId, assets, onOpenMesh, onOpenImage }: Props) {
  const archives = useMemo(() => assets.filter((asset) => asset.archive), [assets]);
  const [query, setQuery] = useState("");
  const [debounced, setDebounced] = useState("");
  const [searching, setSearching] = useState(false);
  const [searchError, setSearchError] = useState<string | null>(null);
  const [hits, setHits] = useState<ArchiveMember[] | null>(null);
  const [summaries, setSummaries] = useState<ArchiveSummary[]>([]);
  const [openArchives, setOpenArchives] = useState<Record<number, boolean>>({});
  const [folders, setFolders] = useState<Record<string, FolderState>>({});
  const [selected, setSelected] = useState<ArchiveMember | null>(null);
  const [detailError, setDetailError] = useState<string | null>(null);

  useEffect(() => {
    const handle = window.setTimeout(() => setDebounced(query.trim()), 220);
    return () => window.clearTimeout(handle);
  }, [query]);

  const loadFolder = useCallback(
    async (assetId: number, prefix: string) => {
      const key = `${assetId}:${prefix}`;
      setFolders((current) => ({
        ...current,
        [key]: { loading: true, error: null, children: current[key]?.children ?? null }
      }));
      try {
        const payload = await api.archiveMembers(modelId, { asset_id: assetId, prefix });
        setSummaries(payload.archives);
        setFolders((current) => ({
          ...current,
          [key]: { loading: false, error: null, children: payload.nodes }
        }));
      } catch (err) {
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

  useEffect(() => {
    if (!debounced) {
      setHits(null);
      setSearchError(null);
      setSearching(false);
      return;
    }
    let cancelled = false;
    setSearching(true);
    setSearchError(null);
    api
      .archiveMembers(modelId, { q: debounced, limit: 80 })
      .then((payload) => {
        if (cancelled) return;
        setHits(payload.members);
        setSummaries(payload.archives);
      })
      .catch((err) => {
        if (!cancelled) setSearchError(err instanceof Error ? err.message : "Search failed");
      })
      .finally(() => {
        if (!cancelled) setSearching(false);
      });
    return () => {
      cancelled = true;
    };
  }, [debounced, modelId]);

  function toggleArchive(assetId: number) {
    setOpenArchives((current) => {
      const next = { ...current, [assetId]: !current[assetId] };
      if (next[assetId] && !folders[`${assetId}:`]) void loadFolder(assetId, "");
      return next;
    });
  }

  function toggleFolder(assetId: number, node: ArchiveMember) {
    const key = `${assetId}:${node.path}`;
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

  async function selectMember(member: ArchiveMember) {
    setSelected(member);
    setDetailError(null);
    if (!member.id || member.directory) return;
    try {
      const payload = await api.archiveMember(member.id);
      setSelected({ ...member, ...payload.member });
    } catch (err) {
      setDetailError(err instanceof Error ? err.message : "Could not load member");
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

  return (
    <section className="rounded-2xl border border-white/10 bg-ink-900/70 p-4">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h2 className="font-display text-xl">Archive</h2>
          <p className="mt-1 text-xs text-slate-500">
            Nested view of zip/3mf. 7z/rar listing is best-effort when <code>7z</code> is on the API host. Members
            stream one at a time — the archive stays on disk.
          </p>
        </div>
        <input
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          placeholder="Search inside archives…"
          className="w-full max-w-sm rounded-full border border-white/10 bg-ink-950 px-4 py-2 text-sm outline-none ring-accent-500 focus:ring-2"
        />
      </div>

      {debounced ? (
        <div className="mt-4">
          {searching ? <p className="text-sm text-slate-500">Searching…</p> : null}
          {searchError ? <p className="text-sm text-rose-300">{searchError}</p> : null}
          {!searching && hits && hits.length === 0 ? (
            <p className="text-sm text-slate-500">No members match “{debounced}”.</p>
          ) : null}
          <ul className="mt-2 space-y-1">
            {(hits || []).map((member) => (
              <MemberRow
                key={`${member.asset_id}:${member.internal_path}`}
                member={member}
                selected={selected?.internal_path === member.internal_path && selected?.asset_id === member.asset_id}
                depth={0}
                onSelect={() => void selectMember(member)}
                onOpenMesh={() => onOpenMesh(member)}
                onOpenImage={() => onOpenImage(member)}
              />
            ))}
          </ul>
        </div>
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
                    {` · ${supportLabel(summary?.support ?? asset.archive_support, asset.kind)}`}
                  </span>
                </button>
                {open ? (
                  <div className="border-t border-white/5 px-2 py-2">
                    {root?.loading && !root.children ? <p className="px-2 text-sm text-slate-500">Loading archive…</p> : null}
                    {root?.error ? <p className="px-2 text-sm text-rose-300">{root.error}</p> : null}
                    {root?.children?.length === 0 ? (
                      <p className="px-2 text-sm text-slate-500">This archive has no indexed members.</p>
                    ) : null}
                    {root?.children?.some((member) => member.listing_source === "placeholder") ? (
                      <p className="mb-2 px-2 text-xs text-amber-200">
                        7z/rar listing needs the <code>7z</code> CLI on the API/worker, then a rescan. Zip/3mf are
                        fully indexed from the central directory.
                      </p>
                    ) : null}
                    <FolderList
                      assetId={asset.id}
                      prefix=""
                      folders={folders}
                      selected={selected}
                      onToggle={toggleFolder}
                      onSelect={(member) => void selectMember(member)}
                      onOpenMesh={onOpenMesh}
                      onOpenImage={onOpenImage}
                      onRetry={loadFolder}
                    />
                  </div>
                ) : null}
              </li>
            );
          })}
        </ul>
      )}

      {selected && !selected.directory ? (
        <div className="mt-4 rounded-xl border border-white/10 bg-ink-950/80 p-3 text-sm">
          <p className="font-mono text-xs text-slate-300">{selected.internal_path}</p>
          <p className="mt-2 text-slate-400">
            {selected.content_type || selected.extension || "file"} · {formatBytes(selected.uncompressed_size)}
            {selected.compressed_size != null ? ` packed (${formatBytes(selected.compressed_size)})` : ""}
          </p>
          {detailError ? <p className="mt-2 text-rose-300">{detailError}</p> : null}
          <div className="mt-3 flex flex-wrap gap-2">
            {selected.mesh && selected.streamable ? (
              <button
                type="button"
                className="rounded-full bg-accent-500 px-3 py-1 text-xs text-ink-950"
                onClick={() => onOpenMesh(selected)}
              >
                Load mesh
              </button>
            ) : null}
            {selected.image && selected.streamable ? (
              <button
                type="button"
                className="rounded-full bg-accent-500 px-3 py-1 text-xs text-ink-950"
                onClick={() => onOpenImage(selected)}
              >
                Open image
              </button>
            ) : null}
            {selected.streamable && selected.id ? (
              <button
                type="button"
                className="rounded-full border border-white/10 px-3 py-1 text-xs text-slate-200"
                onClick={() => void downloadMember(selected).catch((err) => setDetailError(err.message))}
              >
                Download member
              </button>
            ) : (
              <p className="text-xs text-slate-500">This member cannot be streamed from the archive.</p>
            )}
          </div>
        </div>
      ) : null}
    </section>
  );
}

function FolderList({
  assetId,
  prefix,
  folders,
  selected,
  onToggle,
  onSelect,
  onOpenMesh,
  onOpenImage,
  onRetry,
  depth = 0
}: {
  assetId: number;
  prefix: string;
  folders: Record<string, FolderState>;
  selected: ArchiveMember | null;
  onToggle: (assetId: number, node: ArchiveMember) => void;
  onSelect: (member: ArchiveMember) => void;
  onOpenMesh: (member: ArchiveMember) => void;
  onOpenImage: (member: ArchiveMember) => void;
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
              selected={selected?.internal_path === node.internal_path && selected?.asset_id === node.asset_id}
              depth={depth}
              expanded={expanded}
              onSelect={() => {
                onSelect(node);
                if (node.directory) onToggle(assetId, node);
              }}
              onOpenMesh={() => onOpenMesh(node)}
              onOpenImage={() => onOpenImage(node)}
            />
            {node.directory && expanded && child ? (
              <div className="ml-4">
                {child.loading && !child.children ? <p className="px-2 py-1 text-xs text-slate-500">Loading folder…</p> : null}
                {child.error ? (
                  <p className="px-2 py-1 text-xs text-rose-300">
                    {child.error}{" "}
                    <button type="button" className="text-accent-400" onClick={() => void onRetry(assetId, node.path)}>
                      Retry
                    </button>
                  </p>
                ) : null}
                {child.children?.length === 0 ? <p className="px-2 py-1 text-xs text-slate-500">Empty folder</p> : null}
                <FolderList
                  assetId={assetId}
                  prefix={node.path}
                  folders={folders}
                  selected={selected}
                  onToggle={onToggle}
                  onSelect={onSelect}
                  onOpenMesh={onOpenMesh}
                  onOpenImage={onOpenImage}
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
  selected,
  depth,
  expanded,
  onSelect,
  onOpenMesh,
  onOpenImage
}: {
  member: ArchiveMember;
  selected: boolean;
  depth: number;
  expanded?: boolean;
  onSelect: () => void;
  onOpenMesh: () => void;
  onOpenImage: () => void;
}) {
  return (
    <div
      className={`flex items-center gap-2 rounded-lg px-2 py-1 text-xs ${
        selected ? "bg-accent-500/10" : "hover:bg-white/5"
      }`}
      style={{ paddingLeft: `${0.5 + depth * 0.75}rem` }}
    >
      <button type="button" onClick={onSelect} className="min-w-0 flex-1 text-left font-mono text-slate-200">
        {member.directory ? (expanded ? "▾ " : "▸ ") : "· "}
        {member.name || member.internal_path}
        {member.listing_source === "placeholder" ? " (listing pending)" : ""}
      </button>
      {member.has_preview && member.image && member.id ? (
        <ArchiveThumb url={api.archiveMemberPreviewUrl(member.id)} />
      ) : null}
      <span className="shrink-0 text-slate-500">
        {member.directory ? `${member.child_count ?? 0} items` : formatBytes(member.uncompressed_size)}
      </span>
      {member.mesh && member.streamable ? (
        <button type="button" className="shrink-0 text-accent-400" onClick={onOpenMesh}>
          Load
        </button>
      ) : null}
      {member.image && member.streamable ? (
        <button type="button" className="shrink-0 text-accent-400" onClick={onOpenImage}>
          View
        </button>
      ) : null}
    </div>
  );
}

function ArchiveThumb({ url }: { url: string }) {
  const [src, setSrc] = useState<string | null>(null);

  useEffect(() => {
    let objectUrl: string | null = null;
    let cancelled = false;
    const abort = new AbortController();
    fetchAuthedBlob(url, { signal: abort.signal })
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
