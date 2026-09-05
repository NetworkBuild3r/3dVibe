import { DragEvent, useEffect, useMemo, useState } from "react";
import { api, uploadFileResumable, type LibraryInfo } from "../api";

type QueuedFile = {
  key: string;
  file: File;
  relativePath: string;
  progress: number;
  status: "ready" | "uploading" | "done" | "error";
  error?: string;
};

function sanitizeFolder(name: string) {
  return name.replace(/[\\/]+/g, "").replace(/^\.+/, "").trim();
}

type DirReader = { readEntries: (ok: (entries: FileSystemEntry[]) => void, err?: (error: Error) => void) => void };

async function walkEntry(entry: FileSystemEntry, prefix: string, bucket: { file: File; relativePath: string }[]) {
  if (entry.isFile) {
    const file = await new Promise<File>((resolve, reject) => (entry as FileSystemFileEntry).file(resolve, reject));
    const relativePath = prefix ? `${prefix}/${file.name}` : file.name;
    bucket.push({ file, relativePath });
    return;
  }
  if (!entry.isDirectory) return;
  const reader = (entry as FileSystemDirectoryEntry).createReader() as DirReader;
  const nextPrefix = prefix ? `${prefix}/${entry.name}` : entry.name;
  const children: FileSystemEntry[] = [];
  for (;;) {
    const batch = await new Promise<FileSystemEntry[]>((resolve, reject) => reader.readEntries(resolve, reject));
    if (!batch.length) break;
    children.push(...batch);
  }
  for (const child of children) {
    await walkEntry(child, nextPrefix, bucket);
  }
}

async function collectDroppedFiles(event: DragEvent) {
  const items = Array.from(event.dataTransfer?.items || []);
  const collected: { file: File; relativePath: string }[] = [];
  const entries = items.map((item) => item.webkitGetAsEntry?.()).filter((entry): entry is FileSystemEntry => Boolean(entry));

  if (entries.length) {
    for (const entry of entries) {
      await walkEntry(entry, "", collected);
    }
    return collected;
  }

  return Array.from(event.dataTransfer?.files || []).map((file) => ({
    file,
    relativePath: file.webkitRelativePath || file.name
  }));
}

function inferFolder(files: QueuedFile[]) {
  const nested = files.filter((item) => item.relativePath.includes("/"));
  const roots = new Set(nested.map((item) => item.relativePath.split("/")[0]));
  if (roots.size === 1) return [...roots][0];
  return "";
}

function stripRoot(relativePath: string, folder: string) {
  if (relativePath === folder) return relativePath;
  if (folder && (relativePath === `${folder}` || relativePath.startsWith(`${folder}/`))) {
    return relativePath.slice(folder.length + 1) || relativePath;
  }
  return relativePath;
}

export function UploadPage() {
  const [libraries, setLibraries] = useState<LibraryInfo[]>([]);
  const [libraryId, setLibraryId] = useState<number | "">("");
  const [folderName, setFolderName] = useState("");
  const [files, setFiles] = useState<QueuedFile[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [status, setStatus] = useState("");
  const [busy, setBusy] = useState(false);
  const [dragOver, setDragOver] = useState(false);

  useEffect(() => {
    api
      .libraries()
      .then((payload) => {
        const writable = payload.libraries.filter((library) => library.can_upload);
        setLibraries(writable);
        if (writable[0]) setLibraryId(writable[0].id);
      })
      .catch((err) => setError(err instanceof Error ? err.message : "Failed to load libraries"));
  }, []);

  const folderHint = useMemo(() => inferFolder(files), [files]);

  function queue(incoming: { file: File; relativePath: string }[]) {
    setFiles((current) => {
      const next = [...current];
      incoming.forEach((item) => {
        const key = `${item.relativePath}:${item.file.size}:${item.file.lastModified}`;
        if (next.some((existing) => existing.key === key)) return;
        next.push({ key, file: item.file, relativePath: item.relativePath, progress: 0, status: "ready" });
      });
      return next;
    });
    if (!folderName) {
      const guessed = inferFolder(
        incoming.map((item) => ({
          key: item.relativePath,
          file: item.file,
          relativePath: item.relativePath,
          progress: 0,
          status: "ready"
        }))
      );
      if (guessed) setFolderName(sanitizeFolder(guessed));
    }
  }

  async function onDrop(event: DragEvent) {
    event.preventDefault();
    setDragOver(false);
    queue(await collectDroppedFiles(event));
  }

  function onInput(list: FileList | null) {
    if (!list) return;
    queue(Array.from(list).map((file) => ({ file, relativePath: file.webkitRelativePath || file.name })));
  }

  async function startUpload() {
    if (libraryId === "") return;
    const folder = sanitizeFolder(folderName || folderHint);
    if (!folder) {
      setError("Name the shared folder these files belong in.");
      return;
    }
    setFolderName(folder);
    setBusy(true);
    setError(null);
    setStatus("Uploading into the shared library…");
    try {
      for (const item of files) {
        if (item.status === "done") continue;
        setFiles((current) =>
          current.map((row) => (row.key === item.key ? { ...row, status: "uploading", progress: 0 } : row))
        );
        try {
          await uploadFileResumable({
            libraryId,
            folderName: folder,
            file: item.file,
            relativePath: stripRoot(item.relativePath, folder),
            onProgress: (ratio) => {
              setFiles((current) =>
                current.map((row) => (row.key === item.key ? { ...row, progress: ratio } : row))
              );
            }
          });
          setFiles((current) =>
            current.map((row) => (row.key === item.key ? { ...row, status: "done", progress: 1 } : row))
          );
        } catch (err) {
          const message = err instanceof Error ? err.message : "upload failed";
          setFiles((current) =>
            current.map((row) => (row.key === item.key ? { ...row, status: "error", error: message } : row))
          );
        }
      }
      setStatus("Upload finished. A scan is queued so the new files show up for everyone.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="font-display text-3xl text-white">Upload to the shared library</h1>
        <p className="mt-2 max-w-2xl text-sm text-slate-400">
          Files land in the owner&apos;s NFS library root. <strong className="text-slate-200">Everything is shared by
          default.</strong> If you do not want it shared, do not upload. There is no private folder and no hide toggle.
        </p>
      </div>

      <div className="rounded-2xl border border-amber-400/30 bg-amber-400/5 p-4 text-sm text-amber-100">
        Contributors write into the same pile everyone already browses. Authorship is recorded for audit, not for
        hiding models.
      </div>

      <div className="grid gap-4 md:grid-cols-2">
        <label className="text-sm text-slate-300">
          Library
          <select
            className="mt-1 w-full rounded-lg border border-white/10 bg-ink-950 px-3 py-2"
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
        <label className="text-sm text-slate-300">
          Shared folder name
          <input
            className="mt-1 w-full rounded-lg border border-white/10 bg-ink-950 px-3 py-2"
            value={folderName}
            onChange={(event) => setFolderName(event.target.value)}
            placeholder={folderHint || "e.g. cable-comb"}
          />
        </label>
      </div>

      <div
        onDragOver={(event) => {
          event.preventDefault();
          setDragOver(true);
        }}
        onDragLeave={() => setDragOver(false)}
        onDrop={(event) => void onDrop(event)}
        className={`grid min-h-48 place-items-center rounded-2xl border border-dashed px-4 py-10 text-center ${
          dragOver ? "border-accent-400 bg-accent-500/10" : "border-white/15 bg-ink-900/70"
        }`}
      >
        <div>
          <p className="text-slate-200">Drop files or a folder here</p>
          <p className="mt-1 text-xs text-slate-500">Large meshes upload in 1 MB resumable chunks.</p>
          <div className="mt-4 flex flex-wrap justify-center gap-3">
            <label className="cursor-pointer rounded-lg bg-accent-500 px-3 py-1.5 text-sm text-ink-950">
              Choose files
              <input className="hidden" type="file" multiple onChange={(event) => onInput(event.target.files)} />
            </label>
            <label className="cursor-pointer rounded-lg border border-white/15 px-3 py-1.5 text-sm">
              Choose folder
              <input
                className="hidden"
                type="file"
                multiple
                webkitdirectory
                onChange={(event) => onInput(event.target.files)}
              />
            </label>
          </div>
        </div>
      </div>

      {files.length ? (
        <ul className="divide-y divide-white/5 rounded-2xl border border-white/10 bg-ink-900/70">
          {files.map((item) => (
            <li key={item.key} className="px-4 py-3 text-sm">
              <div className="flex items-center justify-between gap-3">
                <span className="truncate text-slate-100">{item.relativePath}</span>
                <span className="text-xs uppercase tracking-wide text-slate-500">{item.status}</span>
              </div>
              <div className="mt-2 h-1.5 overflow-hidden rounded-full bg-white/10">
                <div className="h-full bg-accent-500" style={{ width: `${Math.round(item.progress * 100)}%` }} />
              </div>
              {item.error ? <p className="mt-1 text-xs text-rose-300">{item.error}</p> : null}
            </li>
          ))}
        </ul>
      ) : null}

      {error ? <p className="text-sm text-rose-300">{error}</p> : null}
      {status ? <p className="text-sm text-slate-400">{status}</p> : null}

      <button
        type="button"
        disabled={busy || files.length === 0 || libraryId === ""}
        onClick={() => void startUpload()}
        className="rounded-lg bg-accent-500 px-4 py-2 text-sm font-medium text-ink-950 hover:bg-accent-400 disabled:opacity-60"
      >
        {busy ? "Uploading…" : "Upload to shared library"}
      </button>
    </div>
  );
}
