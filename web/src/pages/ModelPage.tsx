import { useEffect, useMemo, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { api, type ArchiveMember, type ModelDetail, type Printer, type PrintJob } from "../api";
import { ArchivePanel } from "../components/ArchivePanel";
import { ImageViewer } from "../components/ImageViewer";
import { MeshViewer } from "../components/MeshViewer";
import { useAuth } from "../auth";
import { formatBytes } from "../format";

const ACTIVE_PRINT = new Set(["queued", "sending", "printing"]);

type Viewer =
  | { kind: "idle" }
  | { kind: "mesh"; url: string; label: string }
  | { kind: "image"; url: string; label: string };

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
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!id) return;
    api
      .model(id)
      .then((payload) => setModel(payload.model))
      .catch((err) => setError(err instanceof Error ? err.message : "Failed to load"));
  }, [id]);

  const meshAsset = useMemo(() => model?.assets.find((asset) => asset.mesh && asset.kind === "stl"), [model]);
  const printableAssets = useMemo(() => model?.assets.filter((asset) => !asset.archive) || [], [model]);
  const enabledPrinters = useMemo(() => printers.filter((printer) => printer.enabled), [printers]);
  const archiveAssets = useMemo(() => model?.assets.filter((asset) => asset.archive) || [], [model]);

  useEffect(() => {
    api
      .printers()
      .then((payload) => {
        setPrinters(payload.printers);
        const first = payload.printers.find((printer) => printer.enabled);
        if (first) setPrinterId(first.id);
      })
      .catch(() => undefined);
  }, []);

  useEffect(() => {
    if (!model) return;
    const preferred = model.assets.find((asset) => asset.mesh) || model.assets.find((asset) => !asset.archive);
    if (preferred) setAssetId(preferred.id);
  }, [model]);

  useEffect(() => {
    if (!printJob || !ACTIVE_PRINT.has(printJob.status)) return;
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
      setPrintError(err instanceof Error ? err.message : "Could not queue print");
    } finally {
      setPrintBusy(false);
    }
  }

  function openArchiveMesh(member: ArchiveMember) {
    if (!member.id) return;
    setViewer({ kind: "mesh", url: api.archiveMemberContentUrl(member.id), label: member.name || member.internal_path });
  }

  function openArchiveImage(member: ArchiveMember) {
    if (!member.id) return;
    setViewer({
      kind: "image",
      url: api.archiveMemberPreviewUrl(member.id),
      label: member.name || member.internal_path
    });
  }

  if (error) return <p className="text-rose-300">{error}</p>;
  if (!model) return <p className="text-slate-400">Loading model…</p>;

  return (
    <div className="space-y-6">
      <div>
        <Link to="/" className="text-sm text-accent-400">
          ← Library
        </Link>
        <h1 className="mt-2 font-display text-3xl text-white">{model.title}</h1>
        <p className="mt-1 text-slate-400">{model.synopsis || model.folder_name}</p>
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

      <section className="grid gap-6 lg:grid-cols-2">
        <div>
          <div className="mb-3 flex items-center justify-between">
            <h2 className="font-display text-xl">Viewer</h2>
            {meshAsset && viewer.kind !== "mesh" ? (
              <button
                type="button"
                onClick={() =>
                  setViewer({ kind: "mesh", url: api.assetContentUrl(meshAsset.id), label: meshAsset.filename })
                }
                className="rounded-full bg-accent-500 px-3 py-1 text-sm text-ink-950"
              >
                Load mesh
              </button>
            ) : null}
          </div>
          {viewer.kind === "mesh" ? (
            <MeshViewer url={viewer.url} label={viewer.label} />
          ) : viewer.kind === "image" ? (
            <ImageViewer url={viewer.url} label={viewer.label} />
          ) : (
            <div className="grid h-80 place-items-center rounded-2xl border border-dashed border-white/15 bg-ink-900 text-slate-500">
              Preview stays idle until you ask. Archive meshes use the same rule.
            </div>
          )}
        </div>
        <div className="rounded-2xl border border-white/10 bg-ink-900/70 p-4">
          <h2 className="font-display text-xl">Print from browser</h2>
          <p className="mt-2 text-sm text-slate-400">
            The browser talks only to 3dvibe. A worker path-jails the library file and sends it through the printer
            adapter (mock in CI/dev).
          </p>
          {user?.can_print ? (
            <>
              <label className="mt-4 block text-sm text-slate-300">
                Printer
                <select
                  className="mt-1 w-full rounded-lg border border-white/10 bg-ink-950 px-3 py-2"
                  value={printerId}
                  onChange={(event) => setPrinterId(Number(event.target.value))}
                >
                  {enabledPrinters.length === 0 ? <option value="">No enabled printers</option> : null}
                  {enabledPrinters.map((printer) => (
                    <option key={printer.id} value={printer.id}>
                      {printer.name} ({printer.protocol_type} · {printer.host})
                    </option>
                  ))}
                </select>
              </label>
              <label className="mt-3 block text-sm text-slate-300">
                File
                <select
                  className="mt-1 w-full rounded-lg border border-white/10 bg-ink-950 px-3 py-2"
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
              <div className="mt-4 flex flex-wrap items-center gap-3">
                <button
                  type="button"
                  disabled={printBusy || printerId === "" || assetId === ""}
                  onClick={() => void requestPrint()}
                  className="rounded-lg bg-accent-500 px-4 py-2 text-sm font-medium text-ink-950 hover:bg-accent-400 disabled:opacity-60"
                >
                  {printBusy ? "Queueing…" : "Print"}
                </button>
                <Link to="/prints" className="text-sm text-accent-400">
                  Job queue
                </Link>
              </div>
              {printError ? <p className="mt-3 text-sm text-rose-300">{printError}</p> : null}
              {printJob ? (
                <div className="mt-4">
                  <p className="text-sm text-amber-200">
                    {printJob.status} · {printJob.progress}%
                    {printJob.printer_name ? ` · ${printJob.printer_name}` : ""}
                  </p>
                  <div className="mt-2 h-1.5 overflow-hidden rounded-full bg-white/5">
                    <div className="h-full rounded-full bg-accent-500" style={{ width: `${printJob.progress}%` }} />
                  </div>
                  {printJob.note ? <p className="mt-2 text-xs text-slate-500">{printJob.note}</p> : null}
                  {printJob.error_message ? <p className="mt-2 text-xs text-rose-300">{printJob.error_message}</p> : null}
                </div>
              ) : null}
            </>
          ) : (
            <p className="mt-4 text-sm text-slate-500">Ask an owner or contributor to print from this library.</p>
          )}
        </div>
      </section>

      <section className="rounded-2xl border border-white/10 bg-ink-900/70 p-4">
        <h2 className="font-display text-xl">Files</h2>
        <ul className="mt-3 divide-y divide-white/5">
          {model.assets.map((asset) => (
            <li key={asset.id} className="flex items-center justify-between gap-3 py-2 text-sm">
              <div>
                <p className="text-slate-100">{asset.filename}</p>
                <p className="text-xs text-slate-500">
                  {asset.kind} · {formatBytes(asset.byte_size)}
                  {asset.archive ? ` · ${asset.archive_member_count} members` : ""}
                  {asset.archive_truncated ? " · index truncated" : ""}
                </p>
              </div>
              {asset.mesh && asset.kind === "stl" ? (
                <button
                  type="button"
                  className="text-accent-400"
                  onClick={() => setViewer({ kind: "mesh", url: api.assetContentUrl(asset.id), label: asset.filename })}
                >
                  View
                </button>
              ) : null}
            </li>
          ))}
        </ul>
      </section>

      {id && archiveAssets.length > 0 ? (
        <ArchivePanel
          modelId={model.id}
          assets={model.assets}
          onOpenMesh={openArchiveMesh}
          onOpenImage={openArchiveImage}
        />
      ) : null}
    </div>
  );
}
