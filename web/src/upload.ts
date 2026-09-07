export type UploadFileStatus = "ready" | "uploading" | "done" | "error";

export type UploadFileState = {
  status: UploadFileStatus;
};

export type UploadBatchKind = "success" | "partial" | "failed" | "empty";

export type UploadBatchOutcome = {
  kind: UploadBatchKind;
  done: number;
  failed: number;
  pending: number;
  status: string;
  error: string | null;
};

export function fileStatusLabel(status: UploadFileStatus): string {
  if (status === "error") return "failed";
  return status;
}

/** Batch chrome must not claim “finished” when any file failed. */
export function summarizeUploadBatch(files: UploadFileState[]): UploadBatchOutcome {
  const done = files.filter((item) => item.status === "done").length;
  const failed = files.filter((item) => item.status === "error").length;
  const pending = files.filter((item) => item.status === "ready" || item.status === "uploading").length;

  if (!files.length || (done === 0 && failed === 0)) {
    return { kind: "empty", done, failed, pending, status: "", error: null };
  }

  if (failed === 0 && pending === 0) {
    return {
      kind: "success",
      done,
      failed,
      pending,
      status: "Upload finished. A scan is queued so the new files show up for everyone.",
      error: null
    };
  }

  if (failed > 0 && done > 0) {
    const failedLabel = `${failed} file${failed === 1 ? "" : "s"} failed to upload.`;
    return {
      kind: "partial",
      done,
      failed,
      pending,
      status: `${done} uploaded, ${failed} failed. A scan is queued for the files that landed.`,
      error: failedLabel
    };
  }

  return {
    kind: "failed",
    done,
    failed,
    pending,
    status: "Upload failed. Nothing was added to the library.",
    error: failed === 1 ? "1 file failed to upload." : `All ${failed} files failed to upload.`
  };
}
