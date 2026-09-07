export const CURATOR_PROVIDERS = ["stub", "ollama", "xai", "openai", "anthropic"] as const;

export type CuratorProvider = (typeof CURATOR_PROVIDERS)[number];

export const CURATOR_KEY_PROVIDERS = ["xai", "openai", "anthropic"] as const;

export type CuratorKeyProvider = (typeof CURATOR_KEY_PROVIDERS)[number];

export type ApiKeyStatus = "set" | "missing";

/** @deprecated Use ApiKeyStatus */
export type XaiApiKeyStatus = ApiKeyStatus;

export const DEFAULT_OLLAMA_MODEL = "gemma4";

export const CURATOR_KEY_FIELDS = {
  xai: "xai_api_key",
  openai: "openai_api_key",
  anthropic: "anthropic_api_key"
} as const;

export const CURATOR_KEY_STATUS_FIELDS = {
  xai: "xai_api_key_status",
  openai: "openai_api_key_status",
  anthropic: "anthropic_api_key_status"
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
  { id: "xai", label: "xAI" },
  { id: "openai", label: "OpenAI" },
  { id: "anthropic", label: "Anthropic" }
];

export const STUB_HELPER = "CI / offline fixtures.";
export const OLLAMA_DEFAULT_HINT =
  "Default: Ollama + gemma4 (vision). Override model anytime — e.g. gemma4:26b.";
export const KEY_HELPER = "Stored encrypted on the server. Not kept in the browser.";
export const SETTINGS_FOOTER =
  "Applies on the next Refresh proposals. Stub stays for CI. Live default is Ollama + gemma4 when selected.";

const EMPTY_SETTING: CuratorSetting = {
  provider: "ollama",
  ollama_url: null,
  ollama_model: null,
  xai_api_key_status: "missing",
  openai_api_key_status: "missing",
  anthropic_api_key_status: "missing"
};

const RAW_KEY_FIELDS = ["xai_api_key", "openai_api_key", "anthropic_api_key"] as const;

export function isCuratorProvider(value: unknown): value is CuratorProvider {
  return typeof value === "string" && (CURATOR_PROVIDERS as readonly string[]).includes(value);
}

export function isCuratorKeyProvider(value: unknown): value is CuratorKeyProvider {
  return typeof value === "string" && (CURATOR_KEY_PROVIDERS as readonly string[]).includes(value);
}

export function providerLabel(id: CuratorProvider) {
  return PROVIDER_OPTIONS.find((option) => option.id === id)?.label ?? id;
}

export function clearKeyConfirm(provider: CuratorKeyProvider) {
  return `Remove stored ${providerLabel(provider)} key? Next poll falls back to env/stub.`;
}

export function keyStatusFor(setting: CuratorSetting | null, provider: CuratorKeyProvider): ApiKeyStatus {
  if (!setting) return "missing";
  return setting[CURATOR_KEY_STATUS_FIELDS[provider]];
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
  return value === "set" ? "set" : "missing";
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
    xai_api_key_status: asKeyStatus(row.xai_api_key_status),
    openai_api_key_status: asKeyStatus(row.openai_api_key_status),
    anthropic_api_key_status: asKeyStatus(row.anthropic_api_key_status)
  };

  for (const field of RAW_KEY_FIELDS) {
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
