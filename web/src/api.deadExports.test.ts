import { describe, expect, it } from "vitest";
import { api } from "./api";

describe("dead SPA client aliases stay gone", () => {
  it("keeps the HTTP doors the SPA actually calls", () => {
    expect(typeof api.ops).toBe("function");
    expect(typeof api.libraryScan).toBe("function");
    expect(typeof api.extractDuplicate).toBe("function");
    expect(typeof api.extractAndMergeDuplicate).toBe("function");
    expect(typeof api.setCuratorApiKey).toBe("function");
    expect(typeof api.clearCuratorApiKey).toBe("function");
  });

  it("does not re-export grep-dead twin-door or xAI aliases", () => {
    expect(api).not.toHaveProperty("libraryOps");
    expect(api).not.toHaveProperty("extractArchiveMembers");
    expect(api).not.toHaveProperty("extractAndMergeArchiveMembers");
    expect(api).not.toHaveProperty("setCuratorXaiApiKey");
    expect(api).not.toHaveProperty("clearCuratorXaiApiKey");
  });
});
