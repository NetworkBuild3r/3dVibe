import { FormEvent, useEffect, useState } from "react";
import { api, type LibraryInfo, type Printer } from "../api";
import { ProtocolChip } from "../components/PrintMeta";
import { EmptyState, InlineError, ListSkeleton } from "../components/UiStates";
import {
  EMPTY_PRINTERS_COPY,
  MOCK_CI_COPY,
  PROTOCOL_OPTIONS,
  REGISTRY_COPY,
  hasSettingsPayload,
  printerEndpoint,
  printerLastError,
  printerPort,
  printerSettingsPayload,
  printerTimeout
} from "../prints";

const emptyForm = {
  name: "",
  host: "127.0.0.1",
  port: "",
  timeout: "",
  protocolType: "mock",
  notes: "",
  enabled: true
};

export function PrintersPage() {
  const [libraries, setLibraries] = useState<LibraryInfo[]>([]);
  const [printers, setPrinters] = useState<Printer[]>([]);
  const [libraryId, setLibraryId] = useState<number | "">("");
  const [editingId, setEditingId] = useState<number | null>(null);
  const [form, setForm] = useState(emptyForm);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);

  async function refresh() {
    const [libraryPayload, printerPayload] = await Promise.all([api.libraries(), api.printers()]);
    setLibraries(libraryPayload.libraries);
    setPrinters(printerPayload.printers);
    if (libraryId === "" && libraryPayload.libraries[0]) setLibraryId(libraryPayload.libraries[0].id);
  }

  useEffect(() => {
    refresh()
      .catch((err) => setError(err instanceof Error ? err.message : "Failed to load printers"))
      .finally(() => setLoading(false));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  function resetForm() {
    setEditingId(null);
    setForm(emptyForm);
  }

  function edit(printer: Printer) {
    const port = printerPort(printer);
    const timeout = printerTimeout(printer);
    setEditingId(printer.id);
    setLibraryId(printer.library_id);
    setForm({
      name: printer.name,
      host: printer.host,
      port: port != null ? String(port) : "",
      timeout: timeout != null ? String(timeout) : "",
      protocolType: printer.protocol_type,
      notes: printer.notes || "",
      enabled: printer.enabled
    });
  }

  async function onSubmit(event: FormEvent) {
    event.preventDefault();
    if (libraryId === "") return;
    setBusy(true);
    setError(null);
    const existing = editingId ? printers.find((row) => row.id === editingId)?.settings : undefined;
    const settings = printerSettingsPayload(existing, form.port, form.timeout);
    try {
      if (editingId) {
        await api.updatePrinter(editingId, {
          name: form.name.trim(),
          host: form.host.trim(),
          protocol_type: form.protocolType,
          enabled: form.enabled,
          notes: form.notes.trim(),
          settings
        });
      } else {
        await api.createPrinter({
          library_id: libraryId,
          name: form.name.trim(),
          host: form.host.trim(),
          protocol_type: form.protocolType,
          enabled: form.enabled,
          notes: form.notes.trim() || undefined,
          ...(hasSettingsPayload(settings) ? { settings } : {})
        });
      }
      resetForm();
      await refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not save printer");
    } finally {
      setBusy(false);
    }
  }

  async function toggle(printer: Printer) {
    setError(null);
    try {
      await api.updatePrinter(printer.id, { enabled: !printer.enabled });
      await refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not update printer");
    }
  }

  async function remove(printer: Printer) {
    if (!window.confirm(`Remove ${printer.name}?`)) return;
    setError(null);
    try {
      await api.deletePrinter(printer.id);
      if (editingId === printer.id) resetForm();
      await refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not remove printer");
    }
  }

  return (
    <div className="space-y-8">
      <div>
        <h1 className="font-display text-3xl text-white">Printers</h1>
        <p className="mt-2 max-w-2xl text-sm text-slate-400">{REGISTRY_COPY}</p>
      </div>

      <form onSubmit={(event) => void onSubmit(event)} className="rounded-2xl border border-white/10 bg-ink-900/70 p-5">
        <h2 className="font-display text-xl text-white">{editingId ? "Edit printer" : "Add printer"}</h2>
        <div className="mt-4 grid gap-4 md:grid-cols-2">
          <label className="text-sm text-slate-300">
            Library
            <select
              className="mt-1 w-full rounded-lg border border-white/10 bg-ink-950 px-3 py-2"
              value={libraryId}
              onChange={(event) => setLibraryId(Number(event.target.value))}
              disabled={editingId != null}
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
              value={form.name}
              onChange={(event) => setForm((current) => ({ ...current, name: event.target.value }))}
              required
              placeholder="Studio mock"
            />
          </label>
          <label className="text-sm text-slate-300">
            Host / IP
            <input
              className="mt-1 w-full rounded-lg border border-white/10 bg-ink-950 px-3 py-2"
              value={form.host}
              onChange={(event) => setForm((current) => ({ ...current, host: event.target.value }))}
              required
              spellCheck={false}
              autoComplete="off"
              placeholder="10.0.0.40 or 10.0.0.40:3030"
            />
          </label>
          <label className="text-sm text-slate-300">
            Port
            <input
              className="mt-1 w-full rounded-lg border border-white/10 bg-ink-950 px-3 py-2"
              type="number"
              min={1}
              max={65535}
              value={form.port}
              onChange={(event) => setForm((current) => ({ ...current, port: event.target.value }))}
              placeholder="3030"
            />
          </label>
          <label className="text-sm text-slate-300">
            Timeout (seconds)
            <input
              className="mt-1 w-full rounded-lg border border-white/10 bg-ink-950 px-3 py-2"
              type="number"
              min={1}
              step="any"
              value={form.timeout}
              onChange={(event) => setForm((current) => ({ ...current, timeout: event.target.value }))}
              placeholder="15"
            />
          </label>
          <label className="text-sm text-slate-300">
            Protocol
            <select
              className="mt-1 w-full rounded-lg border border-white/10 bg-ink-950 px-3 py-2"
              value={form.protocolType}
              onChange={(event) => setForm((current) => ({ ...current, protocolType: event.target.value }))}
            >
              {PROTOCOL_OPTIONS.map((protocol) => (
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
              value={form.notes}
              onChange={(event) => setForm((current) => ({ ...current, notes: event.target.value }))}
              placeholder="Optional. Camera / resin / consumables stay out of this slice."
            />
          </label>
          <label className="flex items-center gap-2 text-sm text-slate-300">
            <input
              type="checkbox"
              checked={form.enabled}
              onChange={(event) => setForm((current) => ({ ...current, enabled: event.target.checked }))}
            />
            Enabled
          </label>
        </div>
        {error ? (
          <div className="mt-3">
            <InlineError message={error} />
          </div>
        ) : null}
        <div className="mt-4 flex flex-wrap items-center gap-3">
          <button
            type="submit"
            disabled={busy || libraryId === "" || form.name.trim() === "" || form.host.trim() === ""}
            className="rounded-lg bg-accent-500 px-4 py-2 text-sm font-medium text-ink-950 hover:bg-accent-400 disabled:opacity-60"
          >
            {busy ? "Saving…" : editingId ? "Save printer" : "Add printer"}
          </button>
          {editingId ? (
            <button type="button" className="text-sm text-slate-400 hover:text-white" onClick={resetForm}>
              Cancel edit
            </button>
          ) : null}
        </div>
      </form>

      <section className="rounded-2xl border border-white/10 bg-ink-900/70 p-5" aria-busy={loading}>
        <h2 className="font-display text-xl text-white">Registered printers</h2>
        {loading ? (
          <div className="mt-4">
            <ListSkeleton />
          </div>
        ) : printers.length === 0 ? (
          <div className="mt-4">
            <EmptyState copy={EMPTY_PRINTERS_COPY} />
          </div>
        ) : (
          <ul className="mt-4 divide-y divide-white/5">
            {printers.map((row) => {
              const lastError = printerLastError(row);
              return (
                <li key={row.id} className="flex flex-wrap items-center justify-between gap-3 py-3 text-sm">
                  <div>
                    <p className="flex flex-wrap items-center gap-2 text-slate-100">
                      <span>{row.name}</span>
                      <ProtocolChip protocol={row.protocol_type} />
                      {!row.enabled ? <span className="text-xs text-slate-500">disabled</span> : null}
                    </p>
                    <p className="mt-1 text-xs text-slate-500">
                      {printerEndpoint(row)} · {row.library_name}
                      {row.notes ? ` · ${row.notes}` : ""}
                    </p>
                    {lastError ? <p className="mt-1 text-xs text-slate-500">{lastError}</p> : null}
                  </div>
                  <div className="flex gap-3">
                    <button type="button" className="text-accent-400" onClick={() => edit(row)}>
                      Edit
                    </button>
                    <button type="button" className="text-accent-400" onClick={() => void toggle(row)}>
                      {row.enabled ? "Disable" : "Enable"}
                    </button>
                    <button type="button" className="text-rose-300" onClick={() => void remove(row)}>
                      Remove
                    </button>
                  </div>
                </li>
              );
            })}
          </ul>
        )}
      </section>

      <section className="rounded-2xl border border-dashed border-white/10 bg-ink-900/40 p-5 text-sm text-slate-500">
        <p className="font-display text-base text-slate-300">Later</p>
        <p className="mt-2">
          {MOCK_CI_COPY} MainboardID discovery, firmware certify, and a Test print action stay out of this slice. The
          worker is the only process that should open a printer socket.
        </p>
      </section>
    </div>
  );
}
