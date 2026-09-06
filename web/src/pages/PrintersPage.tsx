import { FormEvent, useEffect, useState } from "react";
import { api, type LibraryInfo, type Printer } from "../api";

const PROTOCOLS = [
  { id: "mock", label: "Mock (local stub — always works in CI/dev)" },
  { id: "sdcp", label: "SDCP (LAN — worker talks to the device)" }
];

export function PrintersPage() {
  const [libraries, setLibraries] = useState<LibraryInfo[]>([]);
  const [printers, setPrinters] = useState<Printer[]>([]);
  const [libraryId, setLibraryId] = useState<number | "">("");
  const [name, setName] = useState("");
  const [host, setHost] = useState("127.0.0.1");
  const [protocolType, setProtocolType] = useState("mock");
  const [notes, setNotes] = useState("");
  const [enabled, setEnabled] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function refresh() {
    const [libraryPayload, printerPayload] = await Promise.all([api.libraries(), api.printers()]);
    setLibraries(libraryPayload.libraries);
    setPrinters(printerPayload.printers);
    if (libraryId === "" && libraryPayload.libraries[0]) setLibraryId(libraryPayload.libraries[0].id);
  }

  useEffect(() => {
    refresh().catch((err) => setError(err instanceof Error ? err.message : "Failed to load printers"));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function onSubmit(event: FormEvent) {
    event.preventDefault();
    if (libraryId === "") return;
    setBusy(true);
    setError(null);
    try {
      await api.createPrinter({
        library_id: libraryId,
        name: name.trim(),
        host: host.trim(),
        protocol_type: protocolType,
        enabled,
        notes: notes.trim() || undefined
      });
      setName("");
      setNotes("");
      await refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not save printer");
    } finally {
      setBusy(false);
    }
  }

  async function toggle(printer: Printer) {
    await api.updatePrinter(printer.id, { enabled: !printer.enabled });
    await refresh();
  }

  async function remove(printer: Printer) {
    if (!window.confirm(`Remove ${printer.name}?`)) return;
    await api.deletePrinter(printer.id);
    await refresh();
  }

  return (
    <div className="space-y-8">
      <div>
        <h1 className="font-display text-3xl text-white">Printers</h1>
        <p className="mt-2 max-w-2xl text-sm text-slate-400">
          Register printers the owner can reach on the LAN. The browser never talks to a printer — it only calls the
          3dvibe API. A worker opens the protocol adapter.
        </p>
      </div>

      <form onSubmit={(event) => void onSubmit(event)} className="rounded-2xl border border-white/10 bg-ink-900/70 p-5">
        <h2 className="font-display text-xl text-white">Add printer</h2>
        <div className="mt-4 grid gap-4 md:grid-cols-2">
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
            Name
            <input
              className="mt-1 w-full rounded-lg border border-white/10 bg-ink-950 px-3 py-2"
              value={name}
              onChange={(event) => setName(event.target.value)}
              required
              placeholder="Studio mock"
            />
          </label>
          <label className="text-sm text-slate-300">
            Host / IP
            <input
              className="mt-1 w-full rounded-lg border border-white/10 bg-ink-950 px-3 py-2"
              value={host}
              onChange={(event) => setHost(event.target.value)}
              required
              placeholder="10.0.0.40"
            />
          </label>
          <label className="text-sm text-slate-300">
            Protocol
            <select
              className="mt-1 w-full rounded-lg border border-white/10 bg-ink-950 px-3 py-2"
              value={protocolType}
              onChange={(event) => setProtocolType(event.target.value)}
            >
              {PROTOCOLS.map((protocol) => (
                <option key={protocol.id} value={protocol.id}>
                  {protocol.label}
                </option>
              ))}
            </select>
          </label>
          <label className="text-sm text-slate-300 md:col-span-2">
            Notes
            <input
              className="mt-1 w-full rounded-lg border border-white/10 bg-ink-950 px-3 py-2"
              value={notes}
              onChange={(event) => setNotes(event.target.value)}
              placeholder="Optional. Camera / resin / consumables stay out of this slice."
            />
          </label>
          <label className="flex items-center gap-2 text-sm text-slate-300">
            <input type="checkbox" checked={enabled} onChange={(event) => setEnabled(event.target.checked)} />
            Enabled
          </label>
        </div>
        {error ? <p className="mt-3 text-sm text-rose-300">{error}</p> : null}
        <button
          type="submit"
          disabled={busy || libraryId === "" || name.trim() === ""}
          className="mt-4 rounded-lg bg-accent-500 px-4 py-2 text-sm font-medium text-ink-950 hover:bg-accent-400 disabled:opacity-60"
        >
          {busy ? "Saving…" : "Add printer"}
        </button>
      </form>

      <section className="rounded-2xl border border-white/10 bg-ink-900/70 p-5">
        <h2 className="font-display text-xl text-white">Registered printers</h2>
        <ul className="mt-4 divide-y divide-white/5">
          {printers.map((printer) => (
            <li key={printer.id} className="flex flex-wrap items-center justify-between gap-3 py-3 text-sm">
              <div>
                <p className="text-slate-100">
                  {printer.name}
                  <span className="ml-2 text-xs uppercase tracking-wide text-slate-500">{printer.protocol_type}</span>
                  {!printer.enabled ? <span className="ml-2 text-xs text-amber-300">disabled</span> : null}
                </p>
                <p className="text-xs text-slate-500">
                  {printer.host} · {printer.library_name}
                  {printer.notes ? ` · ${printer.notes}` : ""}
                </p>
              </div>
              <div className="flex gap-2">
                <button type="button" className="text-accent-400" onClick={() => void toggle(printer)}>
                  {printer.enabled ? "Disable" : "Enable"}
                </button>
                <button type="button" className="text-rose-300" onClick={() => void remove(printer)}>
                  Remove
                </button>
              </div>
            </li>
          ))}
          {printers.length === 0 ? <li className="py-3 text-slate-500">No printers yet. Seed adds a Studio mock.</li> : null}
        </ul>
      </section>

      <section className="rounded-2xl border border-dashed border-white/10 bg-ink-900/40 p-5 text-sm text-slate-500">
        <p className="font-display text-base text-slate-300">Later</p>
        <p className="mt-2">
          Resin studio, camera preview, and consumables stay out of this slice. SDCP control is JSON over WebSocket plus
          HTTP upload from <code className="text-slate-400">PrinterAdapters::Sdcp</code> — the browser never opens a
          printer socket. CI keeps <code className="text-slate-400">mock</code>.
        </p>
      </section>
    </div>
  );
}
