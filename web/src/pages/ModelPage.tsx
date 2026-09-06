import { useEffect, useMemo, useState } from "react";
import { Link, useParams } from "react-router-dom";
import {
  api,
  isAbortError,
  memberContentUrl,
  memberPreviewUrl,
  type ArchiveMember,
  type BookmarkFolder,
  type ModelDetail,
  type Printer,
  type PrintJob
} from "../api";
import { ArchivePanel } from "../components/ArchivePanel";
import { CoverMedia } from "../components/CoverMedia";
import { ImageViewer } from "../components/ImageViewer";
import { MeshViewer } from "../components/MeshViewer";
import { JobProgress, JobStatus, ProtocolChip } from "../components/PrintMeta";
import { InlineError } from "../components/UiStates";
import { SaveToShelf } from "../components/SaveToShelf";
import { useAuth } from "../auth";
import { CANT_PREVIEW_COPY, CANCELLED_COPY, displayCaption, memberCaption, memberKind } from "../archives";
import { isViewableMeshAsset, preferredLooseMesh } from "../meshViewer";
import { formatBytes } from "../format";
import {
  BROWSER_NEVER_COPY,
  HISTORY_LINK_LABEL,
  NO_ENABLED_PRINTERS_COPY,
  NO_PRINTABLE_COPY,
  OWNER_ONLY_COPY,
  QUEUING_LABEL,
  SEND_LABEL,
  canRetryJob,
  enqueueErrorMessage,
  firstEnabledPrinterId,
  isJobActive,
  pickerPrinters,
  printableAssetsOf,
  printerOptionLabel,
  shouldShowAssetPicker
} from "../prints";

type Viewer =
  | { kind: "idle" }
  | { kind: "cancelled" }
  | { kind: "unsupported"; caption?: string }
  | {
      kind: "mesh";
      url: string;
      label: string;
      caption?: string;
      filename?: string;
      meshKind?: string | null;
      byteSize?: number | null;
      source: "loose" | "archive";
    }
  | { kind: "image"; url: string; label: string; caption?: string };

export function ModelPage() {
  const { id } = useParams();
  const { user } = useAuth();
  const [model, setModel] = useState<ModelDetail | null>(null);
  const [viewer, setViewer] = useState<Viewer>({ kind: "idle" });
  const [printers, setPrinters] = useState<Printer[]>([]);
  const [printerId, setPrinterId] = useState<number | "">("");
  const [assetId, setAssetId] = useState<number | "">("");
  const [printJob, setPrintJob] = useState<PrintJob | null>(null);
  const [printError, setPrintError] = useState<string | null>(null);
  const [printBusy, setPrintBusy] = useState(false);
  const [folders, setFolders] = useState<BookmarkFolder[]>([]);
  const [selectedAssets, setSelectedAssets] = useState<number[]>([]);
  const [mergeTitle, setMergeTitle] = useState("");
  const [organizeStatus, setOrganizeStatus] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [shelfError, setShelfError] = useState<string | null>(null);

  useEffect(() => {
    setViewer({ kind: "idle" });
  }, [id]);

  useEffect(() => {
    if (!id) return;
    const abort = new AbortController();
    api
      .model(id, abort.signal)
      .then((payload) => setModel(payload.model))
      .catch((err) => {
        if (isAbortError(err) || abort.signal.aborted) return;
        setError(err instanceof Error ? err.message : "Failed to load");
      });
    return () => abort.abort();
  }, [id]);

  const meshAsset = useMemo(() => (model ? preferredLooseMesh(model.assets) : undefined), [model]);
  const printableAssets = useMemo(() => (model ? printableAssetsOf(model.assets) : []), [model]);
  const printerChoices = useMemo(() => pickerPrinters(printers), [printers]);
  const enabledPrinters = useMemo(() => printerChoices.filter((printer) => printer.enabled), [printerChoices]);
  const archiveAssets = useMemo(() => model?.assets.filter((asset) => asset.archive) || [], [model]);

  useEffect(() => {
    api
      .bookmarkFolders()
      .then((payload) => setFolders(payload.bookmark_folders))
      .catch(() => undefined);
  }, []);

  useEffect(() => {
    api
      .printers()
      .then((payload) => {
        setPrinters(payload.printers);
        const first = firstEnabledPrinterId(payload.printers);
        if (first !== "") setPrinterId(first);
      })
      .catch(() => undefined);
  }, []);

  useEffect(() => {
    if (!model) return;
    const preferred = model.assets.find((asset) => asset.mesh) || model.assets.find((asset) => !asset.archive);
    if (preferred) setAssetId(preferred.id);
  }, [model]);

  useEffect(() => {
    if (!printJob || !isJobActive(printJob.status)) return;
    const timer = window.setInterval(() => {
      api
        .printJob(printJob.id)
        .then((payload) => setPrintJob(payload.print_job))
        .catch(() => undefined);
    }, 800);
    return () => window.clearInterval(timer);
  }, [printJob]);

  async function requestPrint() {
    if (!model || printerId === "" || assetId === "") return;
    setPrintBusy(true);
    setPrintError(null);
    try {
      const payload = await api.print(model.id, printerId, assetId);
      setPrintJob(payload.print_job);
    } catch (err) {
      setPrintError(enqueueErrorMessage(err));
    } finally {
      setPrintBusy(false);
    }
  }

  async function retryPrint() {
    if (!printJob) return;
    setPrintBusy(true);
    setPrintError(null);
    try {
      const payload = await api.retryPrint(printJob.id);
      setPrintJob(payload.print_job);
    } catch (err) {
      setPrintError(err instanceof Error ? err.message : "Could not retry print");
    } finally {
      setPrintBusy(false);
    }
  }

  const activeMerge = model?.merges?.find((merge) => !merge.split_at);

  async function toggleLike() {
    if (!model) return;
    setShelfError(null);
    try {
      const payload = model.liked ? await api.unlikeModel(model.id) : await api.likeModel(model.id);
      setModel(payload.model);
    } catch (err) {
      setShelfError(err instanceof Error ? err.message : "Could not update like");
    }
  }

  async function bookmarkTo(folderId: number) {
    if (!model) return;
    setShelfError(null);
    try {
      const payload = await api.addBookmark(folderId, model.id);
      setModel({ ...model, ...payload.model });
    } catch (err) {
      setShelfError(err instanceof Error ? err.message : "Could not save to shelf");
    }
  }

  async function splitMerge() {
    if (!model || !activeMerge) return;
    setOrganizeStatus("Splitting…");
    try {
      await api.splitModel(model.id, activeMerge.id);
      const payload = await api.model(model.id);
      setModel(payload.model);
      setOrganizeStatus("Split complete — source folders are first-level again.");
    } catch (err) {
      setOrganizeStatus(err instanceof Error ? err.message : "Split failed");
    }
  }

  function toggleAsset(id: number) {
    setSelectedAssets((current) => (current.includes(id) ? current.filter((item) => item !== id) : [...current, id]));
  }

  async function mergeAssets() {
    if (!model || selectedAssets.length < 1) return;
    setOrganizeStatus("Merging files…");
    try {
      const payload = await api.mergeModels({
        library_id: model.library_id,
        asset_ids: selectedAssets,
        title: mergeTitle || `${model.title} selection`
      });
      setOrganizeStatus(`Moved into ${payload.model.title}`);
      setSelectedAssets([]);
    } catch (err) {
      setOrganizeStatus(err instanceof Error ? err.message : "Merge failed");
    }
  }

  function closeViewer() {
    setViewer({ kind: "cancelled" });
  }

  function openArchiveMember(member: ArchiveMember, packName: string) {
    const caption = memberCaption(packName, member.internal_path);
    const label = member.name || member.internal_path;
    if (!member.streamable || member.directory) {
      setViewer({ kind: "unsupported", caption });
      return;
    }
    const kind = memberKind(member);
    if (kind === "mesh") {
      const url = memberContentUrl(member);
      if (!url) {
        setViewer({ kind: "unsupported", caption });
        return;
      }
      setViewer({
        kind: "mesh",
        url,
        label,
        caption,
        filename: member.name || member.internal_path,
        meshKind: member.extension,
        byteSize: member.uncompressed_size,
        source: "archive"
      });
      return;
    }
    if (kind === "image") {
      const url = memberPreviewUrl(member);
      if (!url) {
        setViewer({ kind: "unsupported", caption });
        return;
      }
      setViewer({ kind: "image", url, label, caption });
      return;
    }
    setViewer({ kind: "unsupported", caption });
  }

  if (error) return <p className="text-rose-300">{error}</p>;
  if (!model) return <p className="text-slate-400">Loading model…</p>;

  const caption =
    viewer.kind === "mesh" || viewer.kind === "image" || viewer.kind === "unsupported" ? viewer.caption : undefined;

  return (
    <div className="space-y-6">
      <div>
        <Link to="/" className="text-sm text-accent-400">
          ← Library
        </Link>
        <h1 className="mt-2 font-display text-3xl text-white">{model.title}</h1>
        <p className="mt-1 text-slate-400">{model.synopsis || model.folder_name}</p>
        {model.creator ? (
          <p className="mt-2 text-sm text-slate-400">
            <Link to={`/creators/${model.creator.slug}`} className="text-accent-400 hover:text-accent-300">
              {model.creator.name}
            </Link>
          </p>
        ) : null}
        {model.uploaded_by ? (
          <p className="mt-2 text-xs text-slate-500">Uploaded by {model.uploaded_by.display_name} · shared with everyone</p>
        ) : (
          <p className="mt-2 text-xs text-slate-500">Indexed from the shared library disk</p>
        )}
        <div className="mt-3 flex flex-wrap gap-2">
          {model.tags.map((tag) => (
            <span key={tag} className="rounded-full bg-white/5 px-2 py-0.5 text-xs text-slate-300">
              {tag}
            </span>
          ))}
        </div>
      </div>

      <section>
        <div className="mb-3 flex items-center justify-between gap-3">
          <h2 className="font-display text-xl">Viewer</h2>
          <div className="flex flex-wrap items-center gap-2">
            {meshAsset && viewer.kind !== "mesh" ? (
              <button
                type="button"
                onClick={() =>
                  setViewer({
                    kind: "mesh",
                    url: api.assetContentUrl(meshAsset.id),
                    label: meshAsset.filename,
                    filename: meshAsset.filename,
                    meshKind: meshAsset.kind,
                    byteSize: meshAsset.byte_size,
                    source: meshAsset.archive ? "archive" : "loose"
                  })
                }
                className="rounded-full bg-accent-500 px-3 py-1 text-sm text-ink-950"
              >
                Load mesh
              </button>
            ) : null}
            {viewer.kind !== "idle" ? (
              <button type="button" onClick={closeViewer} className="rounded-full border border-white/10 px-3 py-1 text-sm text-slate-300">
                Close
              </button>
            ) : null}
          </div>
        </div>
        {viewer.kind === "mesh" ? (
          <MeshViewer
            key={viewer.url}
            url={viewer.url}
            label={viewer.label}
            filename={viewer.filename}
            meshKind={viewer.meshKind}
            byteSize={viewer.byteSize}
            source={viewer.source}
          />
        ) : viewer.kind === "image" ? (
          <ImageViewer key={viewer.url} url={viewer.url} label={viewer.label} />
        ) : (
          <div className="relative overflow-hidden rounded-2xl border border-white/10 bg-ink-900">
            <div className="grid h-80 place-items-center">
              <CoverMedia model={model} className="absolute inset-0" />
              {viewer.kind === "cancelled" ? (
                <p className="relative z-10 rounded-full bg-ink-950/70 px-3 py-1 text-sm text-slate-400">{CANCELLED_COPY}</p>
              ) : viewer.kind === "unsupported" ? (
                <p className="relative z-10 rounded-full bg-ink-950/70 px-3 py-1 text-sm text-slate-500">{CANT_PREVIEW_COPY}</p>
              ) : null}
            </div>
          </div>
        )}
        {caption ? (
          <p className="mt-2 font-mono text-xs text-slate-500" title={caption}>
            {displayCaption(caption)}
          </p>
        ) : null}
      </section>

      {archiveAssets.length > 0 ? (
        <ArchivePanel
          modelId={model.id}
          modelTitle={model.title}
          assets={model.assets}
          onOpenMember={openArchiveMember}
        />
      ) : null}

      <section className="rounded-2xl border border-white/10 bg-ink-900/70 p-4">
        <h2 className="font-display text-xl">Actions</h2>
        <div className="mt-4 flex flex-wrap items-center gap-3">
          <button
            type="button"
            className={`rounded-full px-3 py-1 text-sm ${model.liked ? "bg-rose-500/15 text-rose-300" : "bg-white/5 text-slate-300"}`}
            onClick={() => void toggleLike()}
          >
            {model.liked ? "Liked" : "Like"} · {model.like_count || 0}
          </button>
          <SaveToShelf
            folders={folders}
            folderIds={model.bookmark_folder_ids}
            onSave={(folderId) => void bookmarkTo(folderId)}
          />
          {activeMerge && user?.can_merge ? (
            <button type="button" className="text-sm text-amber-200" onClick={() => void splitMerge()}>
              Split last merge
            </button>
          ) : null}
        </div>
        {shelfError ? (
          <div className="mt-2">
            <InlineError message={shelfError} />
          </div>
        ) : null}
        {organizeStatus ? <p className="mt-2 text-sm text-accent-300">{organizeStatus}</p> : null}

        <div className="mt-5 border-t border-white/5 pt-4">
          <h3 className="text-sm font-medium text-slate-200">Print</h3>
          <p className="mt-2 text-sm text-slate-500">{BROWSER_NEVER_COPY}</p>
          {user?.can_print ? (
            <div className="mt-3 grid gap-3 md:grid-cols-2">
              <label className="text-sm text-slate-300">
                Printer
                <select
                  className="mt-1 block w-full rounded-lg border border-white/10 bg-ink-950 px-3 py-2"
                  value={printerId}
                  onChange={(event) => setPrinterId(Number(event.target.value))}
                >
                  {enabledPrinters.length === 0 ? <option value="">{NO_ENABLED_PRINTERS_COPY}</option> : null}
                  {printerChoices.map((printer) => (
                    <option key={printer.id} value={printer.id} disabled={!printer.enabled}>
                      {printerOptionLabel(printer)}
                    </option>
                  ))}
                </select>
              </label>
              {shouldShowAssetPicker(printableAssets) ? (
                <label className="text-sm text-slate-300">
                  File
                  <select
                    className="mt-1 block w-full rounded-lg border border-white/10 bg-ink-950 px-3 py-2"
                    value={assetId}
                    onChange={(event) => setAssetId(Number(event.target.value))}
                  >
                    {printableAssets.map((asset) => (
                      <option key={asset.id} value={asset.id}>
                        {asset.filename}
                      </option>
                    ))}
                  </select>
                </label>
              ) : (
                <p className="self-end text-sm text-slate-400">
                  {printableAssets[0]?.filename || NO_PRINTABLE_COPY}
                </p>
              )}
              <div className="flex flex-wrap items-center gap-3 md:col-span-2">
                <button
                  type="button"
                  disabled={printBusy || printerId === "" || assetId === ""}
                  onClick={() => void requestPrint()}
                  className="rounded-lg bg-accent-500 px-4 py-2 text-sm font-medium text-ink-950 hover:bg-accent-400 disabled:opacity-60"
                >
                  {printBusy ? QUEUING_LABEL : SEND_LABEL}
                </button>
              </div>
            </div>
          ) : (
            <p className="mt-3 text-sm text-slate-500">{OWNER_ONLY_COPY}</p>
          )}
          {printError ? <p className="mt-3 text-sm text-rose-300">{printError}</p> : null}
          {printJob ? (
            <div className="mt-4">
              <div className="flex flex-wrap items-center justify-between gap-3">
                <div>
                  <JobStatus status={printJob.status} progress={printJob.progress} />
                  <div className="mt-1 flex flex-wrap items-center gap-2 text-xs text-slate-500">
                    {printJob.printer_name ? <span>{printJob.printer_name}</span> : null}
                    <ProtocolChip protocol={printJob.protocol_type} />
                  </div>
                </div>
                <Link to="/prints" className="text-sm text-accent-400">
                  {HISTORY_LINK_LABEL}
                </Link>
              </div>
              <div className="mt-2">
                <JobProgress status={printJob.status} progress={printJob.progress} />
              </div>
              {printJob.note ? <p className="mt-2 text-xs text-slate-500">{printJob.note}</p> : null}
              {printJob.error_message ? <p className="mt-2 text-xs text-rose-300">{printJob.error_message}</p> : null}
              {canRetryJob(printJob, user?.can_print) ? (
                <button
                  type="button"
                  className="mt-3 text-sm text-rose-300"
                  disabled={printBusy}
                  onClick={() => void retryPrint()}
                >
                  Retry
                </button>
              ) : null}
            </div>
          ) : null}
        </div>
      </section>

      <section className="rounded-2xl border border-white/10 bg-ink-900/70 p-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <h2 className="font-display text-xl">Files</h2>
          {user?.can_merge && selectedAssets.length > 0 ? (
            <div className="flex flex-wrap items-center gap-2">
              <input
                value={mergeTitle}
                onChange={(event) => setMergeTitle(event.target.value)}
                placeholder="New model title"
                className="rounded-lg border border-white/10 bg-ink-950 px-3 py-1.5 text-sm"
              />
              <button type="button" className="text-sm text-accent-300" onClick={() => void mergeAssets()}>
                Merge selected into one model
              </button>
            </div>
          ) : null}
        </div>
        <ul className="mt-3 divide-y divide-white/5">
          {model.assets.map((asset) => (
            <li key={asset.id} className="flex items-center justify-between gap-3 py-2 text-sm">
              <div className="flex items-start gap-2">
                {user?.can_merge ? (
                  <input
                    type="checkbox"
                    className="mt-1"
                    checked={selectedAssets.includes(asset.id)}
                    onChange={() => toggleAsset(asset.id)}
                  />
                ) : null}
                <div>
                  <p className="text-slate-100">{asset.filename}</p>
                  <p className="text-xs text-slate-500">
                    {asset.kind} · {formatBytes(asset.byte_size)}
                    {asset.archive ? ` · ${asset.archive_member_count} members` : ""}
                    {asset.archive_truncated ? " · index truncated" : ""}
                  </p>
                </div>
              </div>
              {isViewableMeshAsset(asset) ? (
                <button
                  type="button"
                  className="text-accent-400"
                  onClick={() =>
                    setViewer({
                      kind: "mesh",
                      url: api.assetContentUrl(asset.id),
                      label: asset.filename,
                      filename: asset.filename,
                      meshKind: asset.kind,
                      byteSize: asset.byte_size,
                      source: asset.archive ? "archive" : "loose"
                    })
                  }
                >
                  Open
                </button>
              ) : null}
            </li>
          ))}
        </ul>
      </section>
    </div>
  );
}
