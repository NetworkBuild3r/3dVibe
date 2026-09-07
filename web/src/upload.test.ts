import { describe, expect, it } from "vitest";
import { fileStatusLabel, summarizeUploadBatch } from "./upload";

describe("upload batch outcome", () => {
  it("does not claim finished when every file failed", () => {
    const outcome = summarizeUploadBatch([
      { status: "error" },
      { status: "error" }
    ]);
    expect(outcome.kind).toBe("failed");
    expect(outcome.status).not.toMatch(/finished/i);
    expect(outcome.status).toMatch(/failed/i);
    expect(outcome.error).toBe("All 2 files failed to upload.");
    expect(outcome.done).toBe(0);
    expect(outcome.failed).toBe(2);
  });

  it("reports a partial batch instead of finished when some files fail", () => {
    const outcome = summarizeUploadBatch([
      { status: "done" },
      { status: "error" },
      { status: "done" }
    ]);
    expect(outcome.kind).toBe("partial");
    expect(outcome.status).not.toMatch(/finished/i);
    expect(outcome.status).toBe("2 uploaded, 1 failed. A scan is queued for the files that landed.");
    expect(outcome.error).toBe("1 file failed to upload.");
    expect(outcome.done).toBe(2);
    expect(outcome.failed).toBe(1);
  });

  it("keeps the finished copy only when every queued file landed", () => {
    const outcome = summarizeUploadBatch([{ status: "done" }, { status: "done" }]);
    expect(outcome.kind).toBe("success");
    expect(outcome.status).toMatch(/Upload finished/);
    expect(outcome.error).toBeNull();
  });

  it("labels per-file errors as failed, not done", () => {
    expect(fileStatusLabel("error")).toBe("failed");
    expect(fileStatusLabel("done")).toBe("done");
    expect(fileStatusLabel("uploading")).toBe("uploading");
    expect(fileStatusLabel("ready")).toBe("ready");
  });
});
