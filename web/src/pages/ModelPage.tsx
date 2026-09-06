import { useEffect, useMemo, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { api, type ArchiveMember, type ModelDetail } from "../api";
import { MeshViewer } from "../components/MeshViewer";

export function ModelPage() {
  const { id } = useParams();
  const [model, setModel] = useState<ModelDetail | null>(null);
  const [members, setMembers] = useState<ArchiveMember[] | null>(null);
  const [viewerAssetId, setViewerAssetId] = useState<number | null>(null);
  const [printNote, setPrintNote] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!id) return;
    api
      .model(id)
      .then((payload) => setModel(payload.model))
      .catch((err) => setError(err instanceof Error ? err.message : "Failed to load"));
  }, [id]);

  const meshAsset = useMemo(() => model?.assets.find((asset) => asset.mesh && asset.kind === "stl"), [model]);

  async function loadArchive() {
    if (!id) return;
    const payload = await api.archiveMembers(id);
    setMembers(payload.members);
  }

  async function requestPrint() {
    if (!model) return;
    const job = await api.print(model.id, meshAsset?.id);
    setPrintNote(`${job.print_job.status}: ${job.print_job.note}`);
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
            {meshAsset && viewerAssetId !== meshAsset.id ? (
              <button
                type="button"
                onClick={() => setViewerAssetId(meshAsset.id)}
                className="rounded-full bg-accent-500 px-3 py-1 text-sm text-ink-950"
              >
                Load mesh
              </button>
            ) : null}
          </div>
          {viewerAssetId ? (
            <MeshViewer url={api.assetContentUrl(viewerAssetId)} label={meshAsset?.filename || "mesh"} />
          ) : (
            <div className="grid h-80 place-items-center rounded-2xl border border-dashed border-white/15 bg-ink-900 text-slate-500">
              Preview stays idle until you ask.
            </div>
          )}
        </div>
        <div className="rounded-2xl border border-white/10 bg-ink-900/70 p-4">
          <h2 className="font-display text-xl">Print from browser</h2>
          <p className="mt-2 text-sm text-slate-400">
            The printer bridge is a placeholder. 3dvibe records the intent and does not open an SDCP session yet.
          </p>
          <button
            type="button"
            onClick={() => void requestPrint()}
            className="mt-4 rounded-lg border border-white/15 px-4 py-2 text-sm hover:border-accent-500/50"
          >
            Queue print (stub)
          </button>
          {printNote ? <p className="mt-3 text-sm text-amber-200">{printNote}</p> : null}
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
                  {asset.kind} · {asset.byte_size} bytes
                  {asset.archive ? ` · ${asset.archive_member_count} members` : ""}
                </p>
              </div>
              {asset.mesh && asset.kind === "stl" ? (
                <button type="button" className="text-accent-400" onClick={() => setViewerAssetId(asset.id)}>
                  View
                </button>
              ) : null}
            </li>
          ))}
        </ul>
      </section>

      <section className="rounded-2xl border border-white/10 bg-ink-900/70 p-4">
        <div className="flex items-center justify-between">
          <h2 className="font-display text-xl">Archive members</h2>
          <button type="button" onClick={() => void loadArchive()} className="text-sm text-accent-400">
            {members ? "Refresh tree" : "Expand archives"}
          </button>
        </div>
        {!members ? (
          <p className="mt-3 text-sm text-slate-500">Members stay collapsed until you expand them.</p>
        ) : (
          <ul className="mt-3 space-y-1 font-mono text-xs text-slate-300">
            {members.map((member) => (
              <li key={member.id}>
                {member.directory ? "▸ " : "· "}
                {member.internal_path}
                {member.previewable ? "  (previewable)" : ""}
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
