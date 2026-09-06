export const CURATOR_PROVIDERS = ["stub", "ollama", "xai"] as const;

export type CuratorProvider = (typeof CURATOR_PROVIDERS)[number];

export type XaiApiKeyStatus = "set" | "missing";

export type CuratorSetting = {
  provider: CuratorProvider;
  ollama_url: string | null;
  ollama_model: string | null;
  xai_api_key_status: XaiApiKeyStatus;
};

export const PROVIDER_OPTIONS: Array<{ id: CuratorProvider; label: string }> = [
  { id: "stub", label: "Stub" },
  { id: "ollama", label: "Ollama" },
  { id: "xai", label: "xAI" }
];

export const STUB_HELPER = "Deterministic fixtures; no cloud calls.";
export const KEY_HELPER = "Stored encrypted on the server. Not kept in the browser.";
export const CLEAR_KEY_CONFIRM = "Remove stored xAI key? Next poll falls back to env/stub.";
export const SETTINGS_FOOTER = "Applies on the next Refresh proposals. Stub stays available.";

const EMPTY_SETTING: CuratorSetting = {
  provider: "stub",
  ollama_url: null,
  ollama_model: null,
  xai_api_key_status: "missing"
};

export function isCuratorProvider(value: unknown): value is CuratorProvider {
  return value === "stub" || value === "ollama" || value === "xai";
}

function asOptionalText(value: unknown) {
  if (typeof value !== "string") return null;
  const text = value.trim();
  return text || null;
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
  return {
    provider: isCuratorProvider(row.provider) ? row.provider : EMPTY_SETTING.provider,
    ollama_url: asOptionalText(row.ollama_url),
    ollama_model: asOptionalText(row.ollama_model),
    xai_api_key_status: row.xai_api_key_status === "set" ? "set" : "missing"
  };
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
