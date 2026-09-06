import { FormEvent, useEffect, useRef, useState } from "react";
import { Link } from "react-router-dom";
import { ApiError, api } from "../api";
import { useAuth } from "../auth";
import { CalmChip } from "../components/CalmChip";
import { EmptyState, InlineError, Pulse } from "../components/UiStates";
import {
  CLEAR_KEY_CONFIRM,
  KEY_HELPER,
  PROVIDER_OPTIONS,
  SETTINGS_FOOTER,
  STUB_HELPER,
  canManageCuratorSettings,
  parseCuratorSetting,
  providerPatchBody,
  type CuratorProvider,
  type CuratorSetting,
  type XaiApiKeyStatus
} from "../curatorSettings";

function KeyStatusChip({ status }: { status: XaiApiKeyStatus }) {
  const missing = status === "missing";
  return (
    <span
      className={`inline-flex rounded-full border px-2 py-0.5 text-[11px] uppercase tracking-wide ${
        missing ? "border-amber-400/30 text-amber-200" : "border-accent-500/40 text-accent-300"
      }`}
    >
      {missing ? "Missing" : "Key set"}
    </span>
  );
}

function SettingsSkeleton() {
  return (
    <div className="rounded-2xl border border-white/10 bg-ink-900/70 p-5" aria-hidden>
      <Pulse className="h-5 w-24" />
      <div className="mt-4 flex gap-2">
        <Pulse className="h-9 w-16 rounded-full" />
        <Pulse className="h-9 w-20 rounded-full" />
        <Pulse className="h-9 w-14 rounded-full" />
      </div>
      <Pulse className="mt-6 h-4 w-2/3" />
      <Pulse className="mt-4 h-10 w-full" />
      <Pulse className="mt-3 h-10 w-full" />
      <Pulse className="mt-5 h-9 w-20" />
    </div>
  );
}

export function CuratorSettingsPage() {
  const { user } = useAuth();
  const owner = canManageCuratorSettings(user);
  const keyInput = useRef<HTMLInputElement | null>(null);
  const mounted = useRef(true);
  const [setting, setSetting] = useState<CuratorSetting | null>(null);
  const [provider, setProvider] = useState<CuratorProvider>("stub");
  const [ollamaUrl, setOllamaUrl] = useState("");
  const [ollamaModel, setOllamaModel] = useState("");
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [savingKey, setSavingKey] = useState(false);
  const [clearingKey, setClearingKey] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [forbidden, setForbidden] = useState(false);
  const [saved, setSaved] = useState<string | null>(null);

  useEffect(() => {
    mounted.current = true;
    return () => {
      mounted.current = false;
    };
  }, []);

  useEffect(() => {
    if (!saved) return;
    const timer = window.setTimeout(() => {
      if (mounted.current) setSaved(null);
    }, 2800);
    return () => window.clearTimeout(timer);
  }, [saved]);

  function applySetting(next: CuratorSetting) {
    const safe = parseCuratorSetting(next);
    setSetting(safe);
    setProvider(safe.provider);
    setOllamaUrl(safe.ollama_url || "");
    setOllamaModel(safe.ollama_model || "");
  }

  async function refresh() {
    setError(null);
    setForbidden(false);
    setLoading(true);
    try {
      const payload = await api.curatorSettings();
      if (!mounted.current) return;
      applySetting(payload.curator_setting);
    } catch (err) {
      if (!mounted.current) return;
      if (err instanceof ApiError && err.status === 403) {
        setForbidden(true);
        return;
      }
      setError(err instanceof Error ? err.message : "Failed to load curator settings");
    } finally {
      if (mounted.current) setLoading(false);
    }
  }

  useEffect(() => {
    if (!owner) return;
    void refresh();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [owner]);

  function clearKeyField() {
    if (keyInput.current) keyInput.current.value = "";
  }

  async function onSaveProvider(event: FormEvent) {
    event.preventDefault();
    if (saving) return;
    setSaving(true);
    setError(null);
    try {
      const payload = await api.updateCuratorSettings(providerPatchBody({ provider, ollama_url: ollamaUrl, ollama_model: ollamaModel }));
      if (!mounted.current) return;
      applySetting(payload.curator_setting);
      setSaved("Saved");
    } catch (err) {
      if (mounted.current) setError(err instanceof Error ? err.message : "Could not save settings");
    } finally {
      if (mounted.current) setSaving(false);
    }
  }

  async function onSaveKey(event: FormEvent) {
    event.preventDefault();
    if (savingKey) return;
    const value = keyInput.current?.value.trim() ?? "";
    if (!value) {
      setError("Enter a key to save.");
      return;
    }
    setSavingKey(true);
    setError(null);
    try {
      const payload = await api.setCuratorXaiApiKey(value);
      clearKeyField();
      if (!mounted.current) return;
      applySetting(payload.curator_setting);
      setSaved("Key saved");
    } catch (err) {
      if (mounted.current) setError(err instanceof Error ? err.message : "Could not save key");
    } finally {
      if (mounted.current) setSavingKey(false);
    }
  }

  async function onClearKey() {
    if (clearingKey) return;
    if (!window.confirm(CLEAR_KEY_CONFIRM)) return;
    setClearingKey(true);
    setError(null);
    try {
      const payload = await api.clearCuratorXaiApiKey();
      clearKeyField();
      if (!mounted.current) return;
      applySetting(payload.curator_setting);
      setSaved("Key removed");
    } catch (err) {
      if (mounted.current) setError(err instanceof Error ? err.message : "Could not clear key");
    } finally {
      if (mounted.current) setClearingKey(false);
    }
  }

  if (!owner) {
    return (
      <div className="space-y-6">
        <h1 className="font-display text-3xl text-white">Curator</h1>
        <EmptyState copy="Owner only" ctaTo="/" ctaLabel="Back to the library" />
      </div>
    );
  }

  if (forbidden) {
    return (
      <div className="space-y-6">
        <h1 className="font-display text-3xl text-white">Curator</h1>
        <EmptyState copy="Owner only" ctaTo="/curation" ctaLabel="Back to Curation" />
      </div>
    );
  }

  const keyStatus = setting?.xai_api_key_status || "missing";

  return (
    <div className="space-y-6">
      <div>
        <h1 className="font-display text-3xl text-white">Curator</h1>
        <p className="mt-2 max-w-2xl text-sm text-slate-400">
          Owner sidecar settings. Saved values override env on the next poll.
        </p>
      </div>

      {error ? <InlineError message={error} onRetry={() => void refresh()} /> : null}

      <section aria-busy={loading}>
        {loading ? (
          <SettingsSkeleton />
        ) : (
          <div className="rounded-2xl border border-white/10 bg-ink-900/70 p-5">
            <form onSubmit={(event) => void onSaveProvider(event)} className="space-y-5">
              <div>
                <p className="text-sm text-slate-300">Provider</p>
                <div role="radiogroup" aria-label="Provider" className="mt-2 flex flex-wrap gap-2">
                  {PROVIDER_OPTIONS.map((option) => (
                    <CalmChip
                      key={option.id}
                      active={provider === option.id}
                      onClick={() => setProvider(option.id)}
                    >
                      {option.label}
                    </CalmChip>
                  ))}
                </div>
                {provider === "stub" ? <p className="mt-3 text-sm text-slate-500">{STUB_HELPER}</p> : null}
              </div>

              {provider === "ollama" ? (
                <div className="grid gap-4 md:grid-cols-2">
                  <label className="text-sm text-slate-300">
                    Base URL
                    <input
                      className="mt-1 w-full rounded-lg border border-white/10 bg-ink-950 px-3 py-2 text-white outline-none ring-accent-500 focus:ring-2"
                      value={ollamaUrl}
                      onChange={(event) => setOllamaUrl(event.target.value)}
                      placeholder="http://host.docker.internal:11434"
                      autoComplete="off"
                    />
                  </label>
                  <label className="text-sm text-slate-300">
                    Model
                    <input
                      className="mt-1 w-full rounded-lg border border-white/10 bg-ink-950 px-3 py-2 text-white outline-none ring-accent-500 focus:ring-2"
                      value={ollamaModel}
                      onChange={(event) => setOllamaModel(event.target.value)}
                      placeholder="llama3.1"
                      autoComplete="off"
                    />
                  </label>
                </div>
              ) : null}

              <div className="flex flex-wrap items-center gap-3">
                <button
                  type="submit"
                  disabled={saving}
                  className="rounded-lg bg-accent-500 px-4 py-2 text-sm font-medium text-ink-950 hover:bg-accent-400 disabled:opacity-60"
                >
                  {saving ? "Saving…" : "Save"}
                </button>
                {saved && !saved.toLowerCase().includes("key") ? (
                  <p className="text-sm text-accent-300" role="status">
                    {saved}
                  </p>
                ) : null}
              </div>
            </form>

            {provider === "xai" ? (
              <form onSubmit={(event) => void onSaveKey(event)} className="mt-8 border-t border-white/5 pt-6">
                <div className="flex flex-wrap items-center gap-2">
                  <h2 className="text-sm text-slate-300">API key</h2>
                  <KeyStatusChip status={keyStatus} />
                </div>
                <label className="mt-4 block text-sm text-slate-300">
                  Set or rotate key
                  <input
                    ref={keyInput}
                    type="password"
                    autoComplete="new-password"
                    name="xai-api-key"
                    className="mt-1 w-full rounded-lg border border-white/10 bg-ink-950 px-3 py-2 text-white outline-none ring-accent-500 focus:ring-2"
                    placeholder="New key"
                  />
                </label>
                <p className="mt-2 text-sm text-slate-500">{KEY_HELPER}</p>
                <div className="mt-4 flex flex-wrap items-center gap-3">
                  <button
                    type="submit"
                    disabled={savingKey}
                    className="rounded-lg bg-accent-500 px-4 py-2 text-sm font-medium text-ink-950 hover:bg-accent-400 disabled:opacity-60"
                  >
                    {savingKey ? "Saving…" : "Save key"}
                  </button>
                  <button
                    type="button"
                    disabled={clearingKey || keyStatus === "missing"}
                    onClick={() => void onClearKey()}
                    className="rounded-lg border border-rose-400/30 px-4 py-2 text-sm text-rose-300 hover:border-rose-400/50 disabled:opacity-50"
                  >
                    {clearingKey ? "Removing…" : "Clear key"}
                  </button>
                  {saved && saved.toLowerCase().includes("key") ? (
                    <p className="text-sm text-accent-300" role="status">
                      {saved}
                    </p>
                  ) : null}
                </div>
              </form>
            ) : null}
          </div>
        )}
      </section>

      <p className="text-sm text-slate-500">
        {SETTINGS_FOOTER}{" "}
        <Link to="/curation" className="text-accent-400 hover:text-accent-300">
          Curation
        </Link>
      </p>
    </div>
  );
}
