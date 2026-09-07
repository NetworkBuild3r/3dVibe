import { describe, expect, it } from "vitest";
import type { CurationPollStatus, CurationProposal } from "./api";
import {
  curationFetchLibraryId,
  pollForLibrary,
  proposalsForLibrary,
  resolveCurationLibrary,
  resolveCurationLibraryId
} from "./curation";

const libraries = [
  {
    id: 1,
    name: "Studio",
    curation: { last_polled_at: "2026-09-01T00:00:00Z", last_provider: "stub", last_error: null }
  },
  {
    id: 2,
    name: "Friends",
    curation: { last_polled_at: "2026-09-07T12:00:00Z", last_provider: "openai", last_error: "sidecar timeout" }
  }
];

const proposals = [
  { id: 10, library_id: 1, summary: "Studio tag" },
  { id: 11, library_id: 2, summary: "Friends rename" },
  { id: 12, library_id: 2, summary: "Friends merge" }
] as Array<Pick<CurationProposal, "id" | "library_id" | "summary">>;

describe("curation library context", () => {
  it("refreshes the selected library, not libraries[0]", () => {
    expect(curationFetchLibraryId(libraries, 2)).toBe(2);
    expect(curationFetchLibraryId(libraries, 1)).toBe(1);
    expect(resolveCurationLibrary(libraries, 2)?.name).toBe("Friends");
  });

  it("defaults to the first library only when nothing is selected", () => {
    expect(resolveCurationLibraryId(libraries, "")).toBe(1);
    expect(curationFetchLibraryId(libraries, "")).toBe(1);
    expect(curationFetchLibraryId([], "")).toBeNull();
  });

  it("keeps a still-valid selection across poll refreshes", () => {
    expect(resolveCurationLibraryId(libraries, 2)).toBe(2);
    expect(resolveCurationLibraryId(libraries.slice(0, 1), 2)).toBe(1);
  });

  it("scopes the queue and poll strip to the selected library", () => {
    expect(proposalsForLibrary(proposals, 2).map((row) => row.id)).toEqual([11, 12]);
    expect(proposalsForLibrary(proposals, "")).toEqual([]);
    expect(pollForLibrary(libraries, 2)?.last_provider).toBe("openai");
    expect(pollForLibrary(libraries, 2)?.last_error).toBe("sidecar timeout");
    expect(pollForLibrary([], 2, libraries)?.last_polled_at).toBe("2026-09-07T12:00:00Z");
    expect(pollForLibrary(libraries, 1)?.last_provider).toBe("stub");
    const emptyPoll: CurationPollStatus | undefined = pollForLibrary(libraries, "");
    expect(emptyPoll).toBeUndefined();
  });
});
