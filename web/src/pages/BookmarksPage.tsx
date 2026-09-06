import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { api, type BookmarkFolder, type ModelCard } from "../api";
import { formatBytes } from "../format";

export function BookmarksPage() {
  const [folders, setFolders] = useState<BookmarkFolder[]>([]);
  const [selectedId, setSelectedId] = useState<number | "likes" | "">("likes");
  const [models, setModels] = useState<ModelCard[]>([]);
  const [name, setName] = useState("");
  const [error, setError] = useState<string | null>(null);

  async function refreshFolders() {
    const payload = await api.bookmarkFolders();
    setFolders(payload.bookmark_folders);
  }

  async function refreshModels(id: number | "likes" | "") {
    if (id === "likes") {
      const payload = await api.likes();
      setModels(payload.models);
      return;
    }
    if (id === "") {
      setModels([]);
      return;
    }
    const payload = await api.bookmarkFolder(id);
    setModels(payload.bookmark_folder.models || []);
  }

  useEffect(() => {
    refreshFolders().catch((err) => setError(err instanceof Error ? err.message : "Failed to load folders"));
  }, []);

  useEffect(() => {
    refreshModels(selectedId).catch((err) => setError(err instanceof Error ? err.message : "Failed to load"));
  }, [selectedId]);

  async function createFolder() {
    if (!name.trim()) return;
    const payload = await api.createBookmarkFolder(name.trim());
    setName("");
    await refreshFolders();
    setSelectedId(payload.bookmark_folder.id);
  }

  async function removeFolder(id: number) {
    await api.deleteBookmarkFolder(id);
    if (selectedId === id) setSelectedId("likes");
    await refreshFolders();
  }

  async function removeBookmark(modelId: number) {
    if (selectedId === "likes") {
      await api.unlikeModel(modelId);
    } else if (selectedId !== "") {
      await api.removeBookmark(selectedId, modelId);
    }
    await refreshModels(selectedId);
    await refreshFolders();
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="font-display text-3xl text-white">Your shelves</h1>
        <p className="mt-2 max-w-2xl text-sm text-slate-400">
          Likes and bookmark folders organize the shared catalog for you. They never hide a model from anyone else.
        </p>
      </div>

      {error ? <p className="text-sm text-rose-300">{error}</p> : null}

      <div className="grid gap-6 lg:grid-cols-[16rem_1fr]">
        <aside className="space-y-3">
          <button
            type="button"
            onClick={() => setSelectedId("likes")}
            className={`w-full rounded-xl px-3 py-2 text-left text-sm ${
              selectedId === "likes" ? "bg-accent-500/15 text-accent-300" : "bg-ink-900 text-slate-300"
            }`}
          >
            Liked
          </button>
          {folders.map((folder) => (
            <div key={folder.id} className="flex items-center gap-2">
              <button
                type="button"
                onClick={() => setSelectedId(folder.id)}
                className={`flex-1 rounded-xl px-3 py-2 text-left text-sm ${
                  selectedId === folder.id ? "bg-accent-500/15 text-accent-300" : "bg-ink-900 text-slate-300"
                }`}
              >
                {folder.name}
                <span className="ml-2 text-xs text-slate-500">{folder.bookmark_count}</span>
              </button>
              <button type="button" className="text-xs text-rose-300" onClick={() => void removeFolder(folder.id)}>
                Delete
              </button>
            </div>
          ))}
          <div className="flex gap-2">
            <input
              value={name}
              onChange={(event) => setName(event.target.value)}
              placeholder="New folder"
              className="w-full rounded-lg border border-white/10 bg-ink-950 px-3 py-2 text-sm"
            />
            <button type="button" className="text-sm text-accent-400" onClick={() => void createFolder()}>
              Add
            </button>
          </div>
        </aside>

        <section className="card-grid">
          {models.map((model) => (
            <div key={model.id} className="rounded-2xl border border-white/10 bg-ink-900/70 p-4">
              <Link to={`/models/${model.id}`} className="font-display text-lg text-white hover:text-accent-400">
                {model.title}
              </Link>
              <p className="mt-1 line-clamp-2 text-sm text-slate-400">{model.synopsis || model.folder_name}</p>
              <p className="mt-3 text-xs text-slate-500">
                {model.asset_count} files · {formatBytes(model.byte_size)}
              </p>
              <button type="button" className="mt-3 text-xs text-rose-300" onClick={() => void removeBookmark(model.id)}>
                Remove
              </button>
            </div>
          ))}
          {models.length === 0 ? <p className="text-sm text-slate-500">Nothing saved here yet.</p> : null}
        </section>
      </div>
    </div>
  );
}
