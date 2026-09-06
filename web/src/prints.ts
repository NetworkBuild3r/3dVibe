import type { Asset, PrintJob, Printer, User } from "./api";

export const JOB_FILTERS = [
  { id: "all", label: "All" },
  { id: "queued", label: "Queued" },
  { id: "sending", label: "Sending" },
  { id: "printing", label: "Printing" },
  { id: "succeeded", label: "Succeeded" },
  { id: "failed", label: "Failed" },
  { id: "cancelled", label: "Cancelled" }
] as const;

export type JobFilter = (typeof JOB_FILTERS)[number]["id"];
export type JobStatusTone = "amber" | "accent" | "rose" | "slate";
export type ProtocolKind = "mock" | "sdcp";

export const ACTIVE_JOB = new Set(["queued", "sending", "printing"]);

export const BROWSER_NEVER_COPY = "Jobs go through the API. Your browser never talks to the printer.";
export const OWNER_ONLY_COPY = "Only the library owner can send a job to a printer.";
export const HISTORY_COPY =
  "Only you can see jobs you queued. Enqueue is owner-only. The browser never talks to the printer. Mock is fine in CI; SDCP-shaped is not certified firmware.";
export const REGISTRY_COPY =
  "Register LAN printers the owner can reach. The browser never talks to a printer — it only calls the 3dvibe API. Mock is the CI/dev path. SDCP-shaped is not certified firmware.";
export const MOCK_CI_COPY = "Mock is the CI/dev path. SDCP-shaped is not certified firmware.";
export const SEND_LABEL = "Send to printer";
export const QUEUING_LABEL = "Queuing…";
export const HISTORY_LINK_LABEL = "View print history";
export const EMPTY_PRINTS_COPY = "No jobs in this filter.";
export const EMPTY_PRINTS_ALL_COPY = "No print jobs yet. The owner can enqueue from a model.";
export const EMPTY_PRINTERS_COPY = "No printers yet. Seed adds a Studio mock.";
export const NO_PRINTABLE_COPY = "No printable files on this model.";
export const NO_ENABLED_PRINTERS_COPY = "No enabled printers";

export const PROTOCOL_OPTIONS = [
  { id: "mock", label: "Mock (CI/dev stub — never opens a socket)" },
  { id: "sdcp", label: "SDCP-shaped (LAN adapter — not certified firmware)" }
] as const;

export function protocolKind(value?: string | null): ProtocolKind | string {
  const kind = (value || "").trim().toLowerCase();
  if (kind === "sdcp") return "sdcp";
  if (kind === "mock") return "mock";
  return kind;
}

export function protocolLabel(value?: string | null) {
  const kind = protocolKind(value);
  if (kind === "sdcp") return "SDCP";
  if (kind === "mock") return "Mock";
  return value?.trim() || "—";
}

export function isJobActive(status?: string | null) {
  return ACTIVE_JOB.has(status || "");
}

export function jobStatusTone(status?: string | null): JobStatusTone {
  if (status === "succeeded") return "accent";
  if (status === "failed") return "rose";
  if (status === "cancelled") return "slate";
  return "amber";
}

export function jobStatusLabel(status?: string | null) {
  const match = JOB_FILTERS.find((item) => item.id === status);
  if (match && match.id !== "all") return match.label;
  if (!status) return "Unknown";
  return status.charAt(0).toUpperCase() + status.slice(1);
}

export function jobStatusClass(status?: string | null) {
  const tone = jobStatusTone(status);
  if (tone === "accent") return "text-accent-400";
  if (tone === "rose") return "text-rose-300";
  if (tone === "slate") return "text-slate-500";
  return "text-amber-200";
}

export function jobProgressClass(status?: string | null) {
  const tone = jobStatusTone(status);
  if (tone === "accent") return "bg-accent-500";
  if (tone === "rose") return "bg-rose-400";
  if (tone === "slate") return "bg-slate-500";
  return "bg-amber-300";
}

export function canRetryJob(job: Pick<PrintJob, "retryable">, canPrint?: boolean) {
  return Boolean(canPrint && job.retryable);
}

export function canCancelJob(job: Pick<PrintJob, "status" | "requested_by">, userId?: number) {
  if (!isJobActive(job.status)) return false;
  if (job.requested_by?.id != null && userId != null) return job.requested_by.id === userId;
  return true;
}

export function emptyPrintsCopy(filter: JobFilter) {
  return filter === "all" ? EMPTY_PRINTS_ALL_COPY : EMPTY_PRINTS_COPY;
}

export function printableAssetsOf(assets: Asset[]) {
  return assets.filter((asset) => !asset.archive);
}

export function shouldShowAssetPicker(assets: Array<{ id: number }>) {
  return assets.length > 1;
}

export function settingText(settings: Record<string, unknown> | null | undefined, key: string) {
  const value = settings?.[key];
  if (typeof value === "string" && value.trim()) return value.trim();
  return null;
}

export function settingNumber(settings: Record<string, unknown> | null | undefined, key: string) {
  const value = settings?.[key];
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" && value.trim()) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

export function hostWithoutPort(host: string) {
  const value = host.trim();
  if (value.startsWith("[")) {
    const match = value.match(/^\[([0-9A-Fa-f:]+)\](?::\d+)?$/);
    return match ? match[1] : value;
  }
  const match = value.match(/^(.+):(\d+)$/);
  if (match && value.indexOf(":") === value.lastIndexOf(":")) return match[1];
  return value;
}

export function portFromHost(host: string) {
  const value = host.trim();
  if (value.startsWith("[")) {
    const match = value.match(/^\[(?:[0-9A-Fa-f:]+)\]:(\d+)$/);
    return match ? Number(match[1]) : null;
  }
  const match = value.match(/:(\d+)$/);
  if (match && value.indexOf(":") === value.lastIndexOf(":")) return Number(match[1]);
  return null;
}

export function printerPort(printer: Pick<Printer, "host" | "settings">) {
  return settingNumber(printer.settings, "port") ?? portFromHost(printer.host);
}

export function printerTimeout(printer: Pick<Printer, "settings">) {
  return settingNumber(printer.settings, "timeout");
}

export function printerEndpoint(printer: Pick<Printer, "host" | "settings">) {
  const host = hostWithoutPort(printer.host) || printer.host;
  const port = printerPort(printer);
  return port ? `${host}:${port}` : host;
}

export function printerLastError(printer: Pick<Printer, "settings"> & { last_error?: string | null; notes?: string | null }) {
  return (
    (typeof printer.last_error === "string" && printer.last_error.trim()) ||
    settingText(printer.settings, "last_error") ||
    settingText(printer.settings, "last_error_message") ||
    null
  );
}

export function printerDisabledReason(printer: Pick<Printer, "enabled" | "disabled_reason" | "last_error" | "settings">) {
  if (printer.enabled) return null;
  return (
    (typeof printer.disabled_reason === "string" && printer.disabled_reason.trim()) ||
    settingText(printer.settings, "disabled_reason") ||
    printerLastError(printer) ||
    "Disabled"
  );
}

export function pickerPrinters(printers: Printer[]) {
  return [...printers].sort((a, b) => Number(b.enabled) - Number(a.enabled) || a.name.localeCompare(b.name));
}

export function printerOptionLabel(printer: Printer) {
  const base = `${printer.name} · ${protocolLabel(printer.protocol_type)} · ${printer.host}`;
  if (printer.enabled) return base;
  return `${base} — ${printerDisabledReason(printer)}`;
}

export function firstEnabledPrinterId(printers: Printer[]) {
  return printers.find((printer) => printer.enabled)?.id ?? "";
}

export function printerSettingsPayload(
  existing: Record<string, unknown> | null | undefined,
  port: string,
  timeout: string
) {
  const next: Record<string, unknown> = { ...(existing || {}) };
  const portValue = port.trim() ? Number(port) : null;
  const timeoutValue = timeout.trim() ? Number(timeout) : null;
  if (portValue != null && Number.isFinite(portValue)) next.port = portValue;
  else delete next.port;
  if (timeoutValue != null && Number.isFinite(timeoutValue) && timeoutValue > 0) next.timeout = timeoutValue;
  else delete next.timeout;
  return next;
}

export function hasSettingsPayload(settings: Record<string, unknown>) {
  return Object.keys(settings).length > 0;
}

export function hasTestPrintApi(client: { testPrint?: unknown }) {
  return typeof client.testPrint === "function";
}

export function canManagePrinters(user?: Pick<User, "can_manage_printers"> | null) {
  return Boolean(user?.can_manage_printers);
}

export function enqueueErrorMessage(error: unknown, fallback = "Could not queue print") {
  return error instanceof Error && error.message.trim() ? error.message : fallback;
}
