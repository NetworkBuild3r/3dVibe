import { describe, expect, it } from "vitest";
import {
  CURATOR_KEY_FIELDS,
  CURATOR_KEY_PROVIDERS,
  CURATOR_PROVIDERS,
  DEFAULT_OLLAMA_MODEL,
  OLLAMA_DEFAULT_HINT,
  PROVIDER_OPTIONS,
  SETTINGS_FOOTER,
  STUB_HELPER,
  canManageCuratorSettings,
  clearKeyConfirm,
  defaultOllamaModelInput,
  isCuratorKeyProvider,
  isCuratorProvider,
  keyStatusFor,
  parseCuratorSetting,
  providerLabel,
  providerPatchBody
} from "./curatorSettings";

const RAW_KEYS = {
  xai_api_key: "sk-xai-must-never-land-in-state",
  openai_api_key: "sk-openai-must-never-land-in-state",
  anthropic_api_key: "sk-anthropic-must-never-land-in-state"
};

describe("curator settings providers", () => {
  it("lists stub, ollama, xAI, OpenAI, and Anthropic in Design order", () => {
    expect(CURATOR_PROVIDERS).toEqual(["stub", "ollama", "xai", "openai", "anthropic"]);
    expect(PROVIDER_OPTIONS.map((option) => option.label)).toEqual([
      "Stub",
      "Ollama",
      "xAI",
      "OpenAI",
      "Anthropic"
    ]);
    expect(CURATOR_KEY_PROVIDERS).toEqual(["xai", "openai", "anthropic"]);
    expect(CURATOR_KEY_FIELDS).toEqual({
      xai: "xai_api_key",
      openai: "openai_api_key",
      anthropic: "anthropic_api_key"
    });
  });

  it("accepts the five backend providers and rejects unknown ids", () => {
    for (const id of CURATOR_PROVIDERS) {
      expect(isCuratorProvider(id)).toBe(true);
    }
    expect(isCuratorProvider("spark")).toBe(false);
    expect(isCuratorProvider("")).toBe(false);
    expect(isCuratorKeyProvider("openai")).toBe(true);
    expect(isCuratorKeyProvider("ollama")).toBe(false);
  });

  it("uses the Design helper and footer copy", () => {
    expect(STUB_HELPER).toBe("CI / offline fixtures.");
    expect(OLLAMA_DEFAULT_HINT).toBe(
      "Default: Ollama + gemma4 (vision). Override model anytime — e.g. gemma4:26b."
    );
    expect(SETTINGS_FOOTER).toBe(
      "Applies on the next Refresh proposals. Stub stays for CI. Live default is Ollama + gemma4 when selected."
    );
    expect(DEFAULT_OLLAMA_MODEL).toBe("gemma4");
    expect(clearKeyConfirm("xai")).toBe("Remove stored xAI key? Next poll falls back to env/stub.");
    expect(clearKeyConfirm("openai")).toBe("Remove stored OpenAI key? Next poll falls back to env/stub.");
    expect(clearKeyConfirm("anthropic")).toBe(
      "Remove stored Anthropic key? Next poll falls back to env/stub."
    );
    expect(providerLabel("xai")).toBe("xAI");
  });
});

describe("parseCuratorSetting", () => {
  it("reads the Backend #44 public shape including OpenAI and Anthropic statuses", () => {
    const setting = parseCuratorSetting({
      curator_setting: {
        provider: "openai",
        ollama_url: " http://ollama.local:11434 ",
        ollama_model: " gemma4:26b ",
        xai_api_key_status: "missing",
        openai_api_key_status: "set",
        anthropic_api_key_status: "missing",
        ...RAW_KEYS
      }
    });

    expect(setting).toEqual({
      provider: "openai",
      ollama_url: "http://ollama.local:11434",
      ollama_model: "gemma4:26b",
      xai_api_key_status: "missing",
      openai_api_key_status: "set",
      anthropic_api_key_status: "missing"
    });
    expect(Object.keys(setting).sort()).toEqual([
      "anthropic_api_key_status",
      "ollama_model",
      "ollama_url",
      "openai_api_key_status",
      "provider",
      "xai_api_key_status"
    ]);
  });

  it("strips accidental raw key fields and never keeps them in client state", () => {
    const setting = parseCuratorSetting({
      provider: "anthropic",
      xai_api_key_status: "set",
      openai_api_key_status: "set",
      anthropic_api_key_status: "set",
      ...RAW_KEYS
    });
    const serialized = JSON.stringify(setting);

    expect(setting.provider).toBe("anthropic");
    expect(setting.xai_api_key_status).toBe("set");
    expect(serialized).not.toContain("sk-");
    expect(serialized).not.toContain("xai_api_key\"");
    expect(serialized).not.toContain("openai_api_key\"");
    expect(serialized).not.toContain("anthropic_api_key\"");
    expect(setting).not.toHaveProperty("xai_api_key");
    expect(setting).not.toHaveProperty("openai_api_key");
    expect(setting).not.toHaveProperty("anthropic_api_key");
  });

  it("defaults a missing or unknown provider to ollama and treats blank statuses as missing", () => {
    expect(parseCuratorSetting(null)).toEqual({
      provider: "ollama",
      ollama_url: null,
      ollama_model: null,
      xai_api_key_status: "missing",
      openai_api_key_status: "missing",
      anthropic_api_key_status: "missing"
    });
    expect(parseCuratorSetting({ provider: "spark", xai_api_key_status: "wat" }).provider).toBe(
      "ollama"
    );
    expect(parseCuratorSetting({ provider: "stub" }).provider).toBe("stub");
  });

  it("prefills gemma4 only when the loaded provider is ollama and the model is empty", () => {
    expect(
      defaultOllamaModelInput({ provider: "ollama", ollama_model: null })
    ).toBe("gemma4");
    expect(
      defaultOllamaModelInput({ provider: "ollama", ollama_model: "gemma4:26b" })
    ).toBe("gemma4:26b");
    expect(defaultOllamaModelInput({ provider: "stub", ollama_model: null })).toBe("");
    expect(defaultOllamaModelInput({ provider: "openai", ollama_model: null })).toBe("");
  });

  it("reads per-provider key status without inventing set", () => {
    const setting = parseCuratorSetting({
      provider: "xai",
      xai_api_key_status: "set",
      openai_api_key_status: "missing"
    });
    expect(keyStatusFor(setting, "xai")).toBe("set");
    expect(keyStatusFor(setting, "openai")).toBe("missing");
    expect(keyStatusFor(setting, "anthropic")).toBe("missing");
    expect(keyStatusFor(null, "openai")).toBe("missing");
  });
});

describe("providerPatchBody", () => {
  it("sends provider plus trimmed Ollama fields and never includes secrets", () => {
    const body = providerPatchBody({
      provider: "ollama",
      ollama_url: " http://host.docker.internal:11434 ",
      ollama_model: " gemma4 "
    });
    expect(body).toEqual({
      provider: "ollama",
      ollama_url: "http://host.docker.internal:11434",
      ollama_model: "gemma4"
    });
    expect(body).not.toHaveProperty("xai_api_key");
    expect(body).not.toHaveProperty("openai_api_key");
    expect(body).not.toHaveProperty("anthropic_api_key");
    expect(
      providerPatchBody({ provider: "stub", ollama_url: "  ", ollama_model: "" })
    ).toEqual({
      provider: "stub",
      ollama_url: null,
      ollama_model: null
    });
  });
});

describe("canManageCuratorSettings", () => {
  it("is the shared gate for /settings/curator, Configure, and the Curator menu", () => {
    expect(canManageCuratorSettings({ role: "owner" })).toBe(true);
    expect(canManageCuratorSettings({ can_invite: true })).toBe(true);
    expect(canManageCuratorSettings({ can_invite: false, can_manage_libraries: true })).toBe(true);
    expect(canManageCuratorSettings({ role: "viewer", can_invite: false, can_manage_libraries: false })).toBe(
      false
    );
    expect(canManageCuratorSettings(null)).toBe(false);
  });
});
