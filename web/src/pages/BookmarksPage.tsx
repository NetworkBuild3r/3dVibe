import { FormEvent, useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { api, type BookmarkFolder, type ModelCard } from "../api";
import { CardGridSkeleton, EmptyState, InlineError, SidebarSkeleton } from "../components/UiStates";
import { formatBytes } from "../format";

export function BookmarksPage() {
  const [folders, setFolders] = useState<BookmarkFolder[]>([]);
  const [selectedId, setSelectedId] = useState<number | "likes">("likes");
  const [models, setModels] = useState<ModelCard[]>([]);
  const [name, setName] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [foldersLoading, setFoldersLoading] = useState(true);
  const [modelsLoading, setModelsLoading] = useState(true);
  const [renamingId, setRenamingId] = useState<number | null>(null);
  const [renameValue, setRenameValue] = useState("");
  const [busy, setBusy] = useState(false);

  async function refreshFolders() {
    const payload = await api.bookmarkFolders();
    setFolders(payload.bookmark_folders);
  }

  async function refreshModels(id: number | "likes") {
    if (id === "likes") {
      const payload = await api.likes();
      setModels(payload.models);
      return;
    }
    const payload = await api.bookmarkFolder(id);
    setModels(payload.bookmark_folder.models || []);
  }

  async function loadFolders() {
    setError(null);
    setFoldersLoading(true);
    try {
      await refreshFolders();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to load folders");
    } finally {
      setFoldersLoading(false);
    }
  }

  async function loadModels(id: number | "likes") {
    setError(null);
    setModelsLoading(true);
    try {
      await refreshModels(id);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to load");
      setModels([]);
    } finally {
      setModelsLoading(false);
    }
  }

  useEffect(() => {
    void loadFolders();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    void loadModels(selectedId);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selectedId]);

  async function retry() {
    await loadFolders();
    await loadModels(selectedId);
  }

  async function createFolder(event?: FormEvent) {
    event?.preventDefault();
    if (!name.trim() || busy) return;
    setBusy(true);
    setError(null);
    try {
      const payload = await api.createBookmarkFolder(name.trim());
      setName("");
      await refreshFolders();
      setSelectedId(payload.bookmark_folder.id);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not create folder");
    } finally {
      setBusy(false);
    }
  }

  function startRename(folder: BookmarkFolder) {
    setRenamingId(folder.id);
    setRenameValue(folder.name);
  }

  async function saveRename(folder: BookmarkFolder) {
    const next = renameValue.trim();
    if (!next || next === folder.name) {
      setRenamingId(null);
      return;
    }
    setBusy(true);
    setError(null);
    try {
      await api.updateBookmarkFolder(folder.id, { name: next });
      setRenamingId(null);
      await refreshFolders();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not rename folder");
    } finally {
      setBusy(false);
    }
  }

  async function removeFolder(folder: BookmarkFolder) {
    if (
      !window.confirm(
        `Delete “${folder.name}”? This removes the shelf, not models from the library.`
      )
    ) {
      return;
    }
    setBusy(true);
    setError(null);
    try {
      await api.deleteBookmarkFolder(folder.id);
      if (selectedId === folder.id) setSelectedId("likes");
      if (renamingId === folder.id) setRenamingId(null);
      await refreshFolders();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not delete folder");
    } finally {
      setBusy(false);
    }
  }

  async function removeBookmark(modelId: number) {
    setBusy(true);
    setError(null);
    try {
      if (selectedId === "likes") {
        await api.unlikeModel(modelId);
      } else {
        await api.removeBookmark(selectedId, modelId);
      }
      await refreshModels(selectedId);
      await refreshFolders();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not remove");
    } finally {
      setBusy(false);
    }
  }

  const selectedFolder = selectedId === "likes" ? null : folders.find((folder) => folder.id === selectedId);
  const emptyCopy = selectedId === "likes" ? "No liked models yet." : "This shelf is empty.";

  return (
    <div className="space-y-6">
      <div>
        <h1 className="font-display text-3xl text-white">Your shelves</h1>
        <p className="mt-2 max-w-2xl text-sm text-slate-400">
          Likes and bookmark folders organize the shared catalog for you. They never hide a model from anyone else.
        </p>
      </div>

      {error ? <InlineError message={error} onRetry={() => void retry()} /> : null}

      <div className="grid gap-6 lg:grid-cols-[16rem_1fr]">
        <aside className="space-y-3">
          {foldersLoading ? (
            <SidebarSkeleton />
          ) : (
            <>
              <button
                type="button"
                onClick={() => setSelectedId("likes")}
                className={`w-full rounded-xl px-3 py-2 text-left text-sm ${
                  selectedId === "likes" ? "bg-accent-500/15 text-accent-300" : "bg-ink-900 text-slate-300"
                }`}
              >
                Liked
                {selectedId === "likes" && !modelsLoading ? (
                  <span className="ml-2 text-xs text-slate-500">{models.length}</span>
                ) : null}
              </button>
              {folders.map((folder) => (
                <div key={folder.id} className="flex items-center gap-2">
                  {renamingId === folder.id ? (
                    <input
                      value={renameValue}
                      autoFocus
                      aria-label={`Rename ${folder.name}`}
                      onChange={(event) => setRenameValue(event.target.value)}
                      onKeyDown={(event) => {
                        if (event.key === "Enter") {
                          event.preventDefault();
                          void saveRename(folder);
                        }
                        if (event.key === "Escape") {
                          event.preventDefault();
                          setRenamingId(null);
                        }
                      }}
                      className="flex-1 rounded-xl border border-accent-500/40 bg-ink-950 px-3 py-2 text-sm"
                    />
                  ) : (
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
                  )}
                  {renamingId === folder.id ? (
                    <>
                      <button type="button" className="text-xs text-accent-400" onClick={() => void saveRename(folder)}>
                        Save
                      </button>
                      <button type="button" className="text-xs text-slate-400" onClick={() => setRenamingId(null)}>
                        Cancel
                      </button>
                    </>
                  ) : (
                    <button type="button" className="text-xs text-slate-400 hover:text-white" onClick={() => startRename(folder)}>
                      Rename
                    </button>
                  )}
                  <button
                    type="button"
                    className="text-xs text-rose-300"
                    disabled={busy}
                    onClick={() => void removeFolder(folder)}
                  >
                    Delete
                  </button>
                </div>
              ))}
              <form className="flex gap-2" onSubmit={(event) => void createFolder(event)}>
                <input
                  value={name}
                  onChange={(event) => setName(event.target.value)}
                  placeholder="New folder"
                  className="w-full rounded-lg border border-white/10 bg-ink-950 px-3 py-2 text-sm"
                />
                <button type="submit" disabled={busy || !name.trim()} className="text-sm text-accent-400 disabled:opacity-50">
                  Add
                </button>
              </form>
            </>
          )}
        </aside>

        <section aria-busy={modelsLoading}>
          {modelsLoading ? (
            <CardGridSkeleton />
          ) : models.length === 0 ? (
            <EmptyState copy={emptyCopy} ctaTo="/" ctaLabel="Browse the library" />
          ) : (
            <div className="card-grid">
              {models.map((model) => (
                <div key={model.id} className="rounded-2xl border border-white/10 bg-ink-900/70 p-4">
                  <Link to={`/models/${model.id}`} className="font-display text-lg text-white hover:text-accent-400">
                    {model.title}
                  </Link>
                  <p className="mt-1 line-clamp-2 text-sm text-slate-400">{model.synopsis || model.folder_name}</p>
                  <p className="mt-3 text-xs text-slate-500">
                    {model.asset_count} files · {formatBytes(model.byte_size)}
                  </p>
                  <button
                    type="button"
                    className="mt-3 text-xs text-rose-300"
                    disabled={busy}
                    onClick={() => void removeBookmark(model.id)}
                  >
                    {selectedId === "likes" ? "Unlike" : "Remove from shelf"}
                  </button>
                </div>
              ))}
            </div>
          )}
          {selectedFolder && !modelsLoading ? (
            <p className="mt-4 text-xs text-slate-500">
              {selectedFolder.name} is your organizer — everyone still sees these models in Library.
            </p>
          ) : null}
        </section>
      </div>
    </div>
  );
}
