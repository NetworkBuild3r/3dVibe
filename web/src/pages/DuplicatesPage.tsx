import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { api, type DuplicateGroup, type LibraryInfo } from "../api";
import { useAuth } from "../auth";
import { formatBytes } from "../format";

export function DuplicatesPage() {
  const { user } = useAuth();
  const [libraries, setLibraries] = useState<LibraryInfo[]>([]);
  const [libraryId, setLibraryId] = useState<number | "">("");
  const [groups, setGroups] = useState<DuplicateGroup[]>([]);
  const [selected, setSelected] = useState<number[]>([]);
  const [title, setTitle] = useState("Merged duplicates");
  const [error, setError] = useState<string | null>(null);
  const [status, setStatus] = useState("");

  useEffect(() => {
    api
      .libraries()
      .then((payload) => {
        setLibraries(payload.libraries);
        if (payload.libraries[0]) setLibraryId(payload.libraries[0].id);
      })
      .catch((err) => setError(err instanceof Error ? err.message : "Failed to load libraries"));
  }, []);

  useEffect(() => {
    if (libraryId === "") return;
    api
      .duplicates(libraryId)
      .then((payload) => {
        setGroups(payload.groups);
        setSelected([]);
      })
      .catch((err) => setError(err instanceof Error ? err.message : "Failed to load duplicates"));
  }, [libraryId]);

  function toggleAsset(id: number) {
    setSelected((current) => (current.includes(id) ? current.filter((item) => item !== id) : [...current, id]));
  }

  async function mergeSelected() {
    if (libraryId === "" || selected.length < 2) return;
    setStatus("Merging…");
    try {
      const payload = await api.mergeModels({ library_id: libraryId, asset_ids: selected, title });
      setStatus(`Merged into ${payload.model.title}`);
      const refreshed = await api.duplicates(libraryId);
      setGroups(refreshed.groups);
      setSelected([]);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Merge failed");
      setStatus("");
    }
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="font-display text-3xl text-white">Likely duplicates</h1>
        <p className="mt-2 max-w-2xl text-sm text-slate-400">
          Exact matches use a streamed content hash. Same filename + size is a heuristic you can review. Merging moves
          files on disk; it does not hide anything from the shared catalog.
        </p>
      </div>

      <div className="flex flex-wrap items-end gap-3">
        <label className="text-sm text-slate-300">
          Library
          <select
            className="mt-1 block rounded-lg border border-white/10 bg-ink-950 px-3 py-2"
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
        {user?.can_merge && selected.length >= 2 ? (
          <>
            <input
              value={title}
              onChange={(event) => setTitle(event.target.value)}
              className="rounded-lg border border-white/10 bg-ink-950 px-3 py-2 text-sm"
            />
            <button
              type="button"
              onClick={() => void mergeSelected()}
              className="rounded-lg bg-accent-500 px-3 py-2 text-sm text-ink-950"
            >
              Merge selected files
            </button>
          </>
        ) : null}
      </div>

      {error ? <p className="text-sm text-rose-300">{error}</p> : null}
      {status ? <p className="text-sm text-accent-300">{status}</p> : null}

      <ul className="space-y-4">
        {groups.map((group) => (
          <li key={group.id} className="rounded-2xl border border-white/10 bg-ink-900/70 p-4">
            <p className="text-sm text-white">
              {group.filename}
              <span className="ml-2 text-xs uppercase tracking-wide text-slate-500">
                {group.confidence} · {group.reason.replace("_", " ")} · {formatBytes(group.byte_size)}
              </span>
            </p>
            <ul className="mt-3 divide-y divide-white/5">
              {group.assets.map((asset) => (
                <li key={asset.id} className="flex flex-wrap items-center justify-between gap-3 py-2 text-sm">
                  <label className="flex items-center gap-2 text-slate-200">
                    {user?.can_merge ? (
                      <input
                        type="checkbox"
                        checked={selected.includes(asset.id)}
                        onChange={() => toggleAsset(asset.id)}
                      />
                    ) : null}
                    <span>
                      {asset.filename}
                      <span className="ml-2 font-mono text-xs text-slate-500">{asset.relative_path}</span>
                    </span>
                  </label>
                  <Link to={`/models/${asset.model_id}`} className="text-accent-400">
                    {asset.model_title}
                  </Link>
                </li>
              ))}
            </ul>
          </li>
        ))}
        {groups.length === 0 ? <li className="text-sm text-slate-500">No likely duplicates in this library.</li> : null}
      </ul>
    </div>
  );
}
