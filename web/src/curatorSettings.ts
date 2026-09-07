export const CURATOR_PROVIDERS = ["stub", "ollama", "xai", "openai", "anthropic"] as const;

export type CuratorProvider = (typeof CURATOR_PROVIDERS)[number];

export const CURATOR_KEY_PROVIDERS = ["xai", "openai", "anthropic"] as const;

export type CuratorKeyProvider = (typeof CURATOR_KEY_PROVIDERS)[number];

export const API_KEY_STATUSES = ["set", "from_env", "missing"] as const;

export type ApiKeyStatus = (typeof API_KEY_STATUSES)[number];

export type KeyStatusTone = "accent" | "slate" | "amber";

export const DEFAULT_OLLAMA_MODEL = "gemma4";

/** One row per cloud-key provider. Status field, HTTP door, and chip label stay in this map. */
export type CuratorKeyPanel = {
  id: CuratorKeyProvider;
  label: string;
  field: `${CuratorKeyProvider}_api_key`;
  statusField: `${CuratorKeyProvider}_api_key_status`;
};

function defineKeyPanel<K extends CuratorKeyProvider>(id: K, label: string) {
  return {
    id,
    label,
    field: `${id}_api_key` as `${K}_api_key`,
    statusField: `${id}_api_key_status` as `${K}_api_key_status`
  };
}

export const CURATOR_KEY_PANELS = {
  xai: defineKeyPanel("xai", "xAI"),
  openai: defineKeyPanel("openai", "OpenAI"),
  anthropic: defineKeyPanel("anthropic", "Anthropic")
} as const satisfies Record<CuratorKeyProvider, CuratorKeyPanel>;

export const CURATOR_KEY_FIELDS = {
  xai: CURATOR_KEY_PANELS.xai.field,
  openai: CURATOR_KEY_PANELS.openai.field,
  anthropic: CURATOR_KEY_PANELS.anthropic.field
} as const;

export const CURATOR_KEY_STATUS_FIELDS = {
  xai: CURATOR_KEY_PANELS.xai.statusField,
  openai: CURATOR_KEY_PANELS.openai.statusField,
  anthropic: CURATOR_KEY_PANELS.anthropic.statusField
} as const;

export type CuratorSetting = {
  provider: CuratorProvider;
  ollama_url: string | null;
  ollama_model: string | null;
  xai_api_key_status: ApiKeyStatus;
  openai_api_key_status: ApiKeyStatus;
  anthropic_api_key_status: ApiKeyStatus;
};

export const PROVIDER_OPTIONS: Array<{ id: CuratorProvider; label: string }> = [
  { id: "stub", label: "Stub" },
  { id: "ollama", label: "Ollama" },
  ...CURATOR_KEY_PROVIDERS.map((id) => ({
    id,
    label: CURATOR_KEY_PANELS[id].label
  }))
];

export const STUB_HELPER = "CI / offline fixtures.";
export const OLLAMA_DEFAULT_HINT =
  "Default: Ollama + gemma4 (vision). Override model anytime — e.g. gemma4:26b.";
export const KEY_HELPER = "Stored encrypted on the server. Not kept in the browser.";
export const SETTINGS_FOOTER =
  "Applies on the next Refresh proposals. Stub stays for CI. Live default is Ollama + gemma4 when selected.";

const MISSING_KEY_STATUSES = {
  xai_api_key_status: "missing",
  openai_api_key_status: "missing",
  anthropic_api_key_status: "missing"
} as const satisfies Pick<CuratorSetting, (typeof CURATOR_KEY_PANELS)[CuratorKeyProvider]["statusField"]>;

const EMPTY_SETTING: CuratorSetting = {
  provider: "ollama",
  ollama_url: null,
  ollama_model: null,
  ...MISSING_KEY_STATUSES
};

export function isCuratorProvider(value: unknown): value is CuratorProvider {
  return typeof value === "string" && (CURATOR_PROVIDERS as readonly string[]).includes(value);
}

export function isCuratorKeyProvider(value: unknown): value is CuratorKeyProvider {
  return typeof value === "string" && (CURATOR_KEY_PROVIDERS as readonly string[]).includes(value);
}

export function curatorKeyPanel(provider: CuratorKeyProvider) {
  return CURATOR_KEY_PANELS[provider];
}

export function curatorKeyPanelFor(provider: CuratorProvider) {
  return isCuratorKeyProvider(provider) ? CURATOR_KEY_PANELS[provider] : null;
}

export function curatorKeyEndpoint(provider: CuratorKeyProvider) {
  return `/curator_settings/${CURATOR_KEY_PANELS[provider].field}`;
}

export function curatorKeyPutBody(provider: CuratorKeyProvider, apiKey: string) {
  return { [CURATOR_KEY_PANELS[provider].field]: apiKey };
}

export function providerLabel(id: CuratorProvider) {
  if (isCuratorKeyProvider(id)) return CURATOR_KEY_PANELS[id].label;
  return PROVIDER_OPTIONS.find((option) => option.id === id)?.label ?? id;
}

export function clearKeyConfirm(provider: CuratorKeyProvider) {
  return `Remove stored ${providerLabel(provider)} key? Next poll falls back to env/stub.`;
}

export function isApiKeyStatus(value: unknown): value is ApiKeyStatus {
  return typeof value === "string" && (API_KEY_STATUSES as readonly string[]).includes(value);
}

export function keyStatusFor(setting: CuratorSetting | null, provider: CuratorKeyProvider): ApiKeyStatus {
  if (!setting) return "missing";
  return setting[CURATOR_KEY_STATUS_FIELDS[provider]];
}

export function keyStatusLabel(status: ApiKeyStatus) {
  if (status === "set") return "Key set";
  if (status === "from_env") return "From env";
  return "Missing";
}

export function keyStatusTone(status: ApiKeyStatus): KeyStatusTone {
  if (status === "set") return "accent";
  if (status === "from_env") return "slate";
  return "amber";
}

const KEY_STATUS_CHIP_CLASS: Record<KeyStatusTone, string> = {
  accent: "border-accent-500/40 text-accent-300",
  slate: "border-white/10 text-slate-300",
  amber: "border-amber-400/30 text-amber-200"
};

export function keyStatusChipClass(status: ApiKeyStatus) {
  return KEY_STATUS_CHIP_CLASS[keyStatusTone(status)];
}

/** Only a persisted sidecar key can be cleared. ENV fallbacks stay until a stored key is saved. */
export function canClearStoredKey(status: ApiKeyStatus) {
  return status === "set";
}

export function defaultOllamaModelInput(setting: Pick<CuratorSetting, "provider" | "ollama_model">) {
  if (setting.ollama_model) return setting.ollama_model;
  return setting.provider === "ollama" ? DEFAULT_OLLAMA_MODEL : "";
}

function asOptionalText(value: unknown) {
  if (typeof value !== "string") return null;
  const text = value.trim();
  return text || null;
}

function asKeyStatus(value: unknown): ApiKeyStatus {
  return isApiKeyStatus(value) ? value : "missing";
}

function settingRecord(raw: unknown): Record<string, unknown> {
  if (!raw || typeof raw !== "object") return {};
  const envelope = raw as { curator_setting?: unknown };
  if (envelope.curator_setting && typeof envelope.curator_setting === "object") {
    return envelope.curator_setting as Record<string, unknown>;
  }
  return raw as Record<string, unknown>;
}

/** Pick only public fields. Never keep a raw key from a payload. */
export function parseCuratorSetting(raw: unknown): CuratorSetting {
  const row = settingRecord(raw);
  const parsed: CuratorSetting = {
    provider: isCuratorProvider(row.provider) ? row.provider : EMPTY_SETTING.provider,
    ollama_url: asOptionalText(row.ollama_url),
    ollama_model: asOptionalText(row.ollama_model),
    ...MISSING_KEY_STATUSES
  };

  for (const id of CURATOR_KEY_PROVIDERS) {
    const { field, statusField } = CURATOR_KEY_PANELS[id];
    parsed[statusField] = asKeyStatus(row[statusField]);
    delete (parsed as Record<string, unknown>)[field];
  }

  return parsed;
}

export function providerPatchBody(input: {
  provider: CuratorProvider;
  ollama_url: string;
  ollama_model: string;
}) {
  return {
    provider: input.provider,
    ollama_url: input.ollama_url.trim() || null,
    ollama_model: input.ollama_model.trim() || null
  };
}

export function canManageCuratorSettings(user: {
  can_invite?: boolean;
  can_manage_libraries?: boolean;
  role?: string;
} | null) {
  return Boolean(user?.can_invite || user?.can_manage_libraries || user?.role === "owner");
}
