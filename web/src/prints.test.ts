import { describe, expect, it } from "vitest";
import type { Printer, PrintJob } from "./api";
import { api } from "./api";
import {
  BROWSER_NEVER_COPY,
  canCancelJob,
  canRetryJob,
  emptyPrintsCopy,
  enqueueErrorMessage,
  firstEnabledPrinterId,
  hasTestPrintApi,
  isJobActive,
  jobProgressClass,
  jobStatusClass,
  jobStatusLabel,
  jobStatusTone,
  pickerPrinters,
  printerDisabledReason,
  printerEndpoint,
  printerLastError,
  printerOptionLabel,
  printerPort,
  printerSettingsPayload,
  printerTimeout,
  protocolKind,
  protocolLabel,
  shouldShowAssetPicker
} from "./prints";

function printer(overrides: Partial<Printer> = {}): Printer {
  return {
    id: 1,
    library_id: 1,
    library_name: "Studio",
    name: "Studio mock",
    host: "127.0.0.1",
    protocol_type: "mock",
    enabled: true,
    notes: null,
    settings: {},
    created_at: "2026-09-06T00:00:00Z",
    updated_at: "2026-09-06T00:00:00Z",
    ...overrides
  };
}

function job(overrides: Partial<PrintJob> = {}): PrintJob {
  return {
    id: 9,
    library_id: 1,
    printer_id: 1,
    printer_name: "Studio mock",
    protocol_type: "mock",
    model_id: 3,
    model_title: "Signal Horn",
    asset_id: 4,
    filename: "horn.stl",
    status: "failed",
    progress: 40,
    printer_hint: "Studio mock",
    note: null,
    error_message: "timeout",
    retryable: true,
    remote_ref: null,
    requested_by: { id: 1, display_name: "Owner" },
    started_at: null,
    finished_at: null,
    created_at: "2026-09-06T00:00:00Z",
    updated_at: "2026-09-06T00:00:00Z",
    ...overrides
  };
}

describe("print honesty bind", () => {
  it("labels mock vs SDCP protocols", () => {
    expect(protocolKind("SDCP")).toBe("sdcp");
    expect(protocolLabel("sdcp")).toBe("SDCP");
    expect(protocolLabel("mock")).toBe("Mock");
    expect(protocolLabel(null)).toBe("—");
  });

  it("colors queued/sending/printing amber, succeeded accent, failed rose, cancelled slate", () => {
    expect(jobStatusTone("queued")).toBe("amber");
    expect(jobStatusTone("sending")).toBe("amber");
    expect(jobStatusTone("printing")).toBe("amber");
    expect(jobStatusTone("succeeded")).toBe("accent");
    expect(jobStatusTone("failed")).toBe("rose");
    expect(jobStatusTone("cancelled")).toBe("slate");
    expect(jobStatusLabel("printing")).toBe("Printing");
    expect(jobStatusClass("failed")).toContain("rose");
    expect(jobProgressClass("queued")).toContain("amber");
    expect(isJobActive("sending")).toBe(true);
    expect(isJobActive("succeeded")).toBe(false);
  });

  it("retries only when retryable and owner can_print", () => {
    expect(canRetryJob(job({ retryable: true }), true)).toBe(true);
    expect(canRetryJob(job({ retryable: true, status: "cancelled" }), true)).toBe(true);
    expect(canRetryJob(job({ retryable: false }), true)).toBe(false);
    expect(canRetryJob(job({ retryable: true }), false)).toBe(false);
    expect(canRetryJob(job({ retryable: undefined }), true)).toBe(false);
  });

  it("cancels active jobs for the requester", () => {
    expect(canCancelJob(job({ status: "printing" }), 1)).toBe(true);
    expect(canCancelJob(job({ status: "printing" }), 2)).toBe(false);
    expect(canCancelJob(job({ status: "failed" }), 1)).toBe(false);
  });

  it("formats host:port from settings or host suffix", () => {
    expect(printerEndpoint(printer({ host: "10.0.0.40", settings: { port: 3030 } }))).toBe("10.0.0.40:3030");
    expect(printerEndpoint(printer({ host: "10.0.0.40:3030", settings: {} }))).toBe("10.0.0.40:3030");
    expect(printerPort(printer({ host: "10.0.0.40", settings: { port: "80" } }))).toBe(80);
    expect(printerTimeout(printer({ settings: { timeout: 15 } }))).toBe(15);
    expect(printerEndpoint(printer({ host: "127.0.0.1" }))).toBe("127.0.0.1");
  });

  it("shows disabled printers muted with an API reason when present", () => {
    const disabled = printer({
      id: 2,
      name: "Garage",
      host: "10.0.0.8",
      protocol_type: "sdcp",
      enabled: false,
      disabled_reason: "offline"
    });
    expect(printerDisabledReason(disabled)).toBe("offline");
    expect(printerOptionLabel(disabled)).toBe("Garage · SDCP · 10.0.0.8 — offline");
    expect(printerDisabledReason(printer({ enabled: false }))).toBe("Disabled");
    expect(printerLastError(printer({ last_error: "busy" }))).toBe("busy");
    expect(firstEnabledPrinterId([disabled, printer()])).toBe(1);
  });

  it("lists enabled printers first in the picker", () => {
    const rows = pickerPrinters([
      printer({ id: 2, name: "Zulu", enabled: false }),
      printer({ id: 3, name: "Alpha", enabled: true }),
      printer({ id: 4, name: "Beta", enabled: true })
    ]);
    expect(rows.map((row) => row.name)).toEqual(["Alpha", "Beta", "Zulu"]);
  });

  it("merges port and timeout into settings without dropping other keys", () => {
    expect(printerSettingsPayload({ token: "abc", port: 80 }, "3030", "20")).toEqual({
      token: "abc",
      port: 3030,
      timeout: 20
    });
    expect(printerSettingsPayload({ port: 80, timeout: 5 }, "", "")).toEqual({});
  });

  it("shows the file picker only when more than one loose asset exists", () => {
    expect(shouldShowAssetPicker([{ id: 1 }])).toBe(false);
    expect(shouldShowAssetPicker([{ id: 1 }, { id: 2 }])).toBe(true);
  });

  it("keeps enqueue errors honest and skips Test print unless the API exists", () => {
    expect(enqueueErrorMessage(new Error("printer is disabled"))).toBe("printer is disabled");
    expect(hasTestPrintApi(api)).toBe(false);
    expect(BROWSER_NEVER_COPY).toMatch(/never talks to the printer/);
    expect(emptyPrintsCopy("all")).toMatch(/owner can enqueue/);
    expect(emptyPrintsCopy("failed")).toBe("No jobs in this filter.");
  });
});
