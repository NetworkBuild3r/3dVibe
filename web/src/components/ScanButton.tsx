import { useEffect, useState } from "react";
import { api, type LibraryInfo } from "../api";
import { useAuth } from "../auth";
import { IconScan } from "./Icons";

export function ScanButton() {
  const { user } = useAuth();
  const [libraries, setLibraries] = useState<LibraryInfo[]>([]);
  const [busy, setBusy] = useState(false);
  const [note, setNote] = useState("");

  const canScan = Boolean(user?.can_manage_libraries || user?.can_invite);

  useEffect(() => {
    if (!canScan) return;
    api
      .libraries()
      .then((payload) => setLibraries(payload.libraries))
      .catch(() => undefined);
  }, [canScan]);

  const target = libraries.find((library) => library.can_scan) || libraries[0];

  async function scan() {
    if (!target || busy) return;
    setBusy(true);
    setNote("");
    try {
      await api.scanLibrary(target.id);
      setNote("Queued");
    } catch (err) {
      setNote(err instanceof Error ? err.message : "Scan failed");
    } finally {
      setBusy(false);
      window.setTimeout(() => setNote(""), 2400);
    }
  }

  if (!canScan || !target) return null;

  return (
    <div className="flex items-center gap-2">
      <button
        type="button"
        onClick={() => void scan()}
        disabled={busy}
        className="inline-flex items-center gap-2 rounded-full border border-white/10 px-3 py-1.5 text-sm text-slate-200 hover:border-accent-500/40 hover:text-white disabled:opacity-60"
      >
        <IconScan />
        {busy ? "Scanning…" : "Scan"}
      </button>
      {note ? <span className={`text-xs ${note === "Queued" ? "text-slate-500" : "text-rose-300"}`}>{note}</span> : null}
    </div>
  );
}
