import {
  curatorKeyEndpoint,
  curatorKeyPutBody,
  parseCuratorSetting,
  type CuratorKeyProvider,
  type CuratorProvider
} from "./curatorSettings";
import type {
  ArchiveExtractPayload,
  ArchiveExtractRequest,
  ArchiveMember,
  ArchiveMemberDetail,
  ArchiveTreeResponse,
  BookmarkFolder,
  Creator,
  CurationPollStatus,
  CurationProposal,
  DuplicateGroup,
  DuplicateReview,
  DuplicateStatus,
  DuplicatesPayload,
  Invite,
  LibraryInfo,
  LibraryMember,
  LibraryScanDetail,
  LibraryUpload,
  MeiliHealth,
  ModelCard,
  ModelDetail,
  ModelMerge,
  OpsSnapshot,
  PrintJob,
  Printer,
  User
} from "./types";

const API_BASE = import.meta.env.VITE_API_BASE_URL || "/api/v1";

function token(): string | null {
  return localStorage.getItem("vibe_token");
}

export function setToken(value: string | null) {
  if (value) localStorage.setItem("vibe_token", value);
  else localStorage.removeItem("vibe_token");
}

export class ApiError extends Error {
  status: number;
  code: string;
  data: Record<string, unknown>;

  constructor(message: string, status: number, code = "", data: Record<string, unknown> = {}) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.code = code;
    this.data = data;
  }
}

async function request<T>(path: string, init: RequestInit = {}): Promise<T> {
  const headers = new Headers(init.headers);
  headers.set("Accept", "application/json");
  if (init.body && !(init.body instanceof FormData) && !(init.body instanceof Blob)) {
    headers.set("Content-Type", "application/json");
  }
  const current = token();
  if (current) headers.set("Authorization", `Bearer ${current}`);

  const response = await fetch(`${API_BASE}${path}`, { ...init, headers });
  if (init.signal?.aborted) throw new DOMException("Aborted", "AbortError");
  if (response.status === 204) return undefined as T;
  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    const details = Array.isArray(data.details) ? data.details.filter(Boolean).join(" ") : "";
    const code = typeof data.error === "string" ? data.error : "";
    const message =
      details || (typeof data.message === "string" && data.message) || code || `Request failed (${response.status})`;
    throw new ApiError(message, response.status, code, data && typeof data === "object" ? data : {});
  }
  return data as T;
}

export const api = {
  login: (email: string, password: string) =>
    request<{ token: string; user: User }>("/session", {
      method: "POST",
      body: JSON.stringify({ email, password })
    }),
  me: () => request<{ user: User }>("/me"),
  logout: () => request<void>("/session", { method: "DELETE" }),
  libraries: () => request<{ libraries: LibraryInfo[] }>("/libraries"),
  library: (id: number | string) => request<{ library: LibraryInfo }>(`/libraries/${id}`),
  libraryMembers: (id: number | string) =>
    request<{ members: LibraryMember[] }>(`/libraries/${id}/members`),
  libraryScan: (id: number | string) => request<LibraryScanDetail>(`/libraries/${id}/scan`),
  ops: (libraryId?: number | string) => {
    const suffix = libraryId != null ? `?library_id=${encodeURIComponent(String(libraryId))}` : "";
    return request<{ meili?: MeiliHealth; libraries?: OpsSnapshot[]; ops?: OpsSnapshot }>(`/ops${suffix}`);
  },
  scanLibrary: (id: number, pathPrefix?: string) =>
    request<{ queued: boolean; library_id: number; library: LibraryInfo }>(`/libraries/${id}/scan`, {
      method: "POST",
      body: JSON.stringify(pathPrefix ? { path_prefix: pathPrefix } : {})
    }),
  creators: () => request<{ creators: Creator[] }>("/creators"),
  creator: (idOrSlug: string | number, cursor?: string | null, limit = 24) => {
    const params = new URLSearchParams({ limit: String(limit) });
    if (cursor) params.set("cursor", cursor);
    return request<{ creator: Creator; models: ModelCard[]; next_cursor: number | null }>(
      `/creators/${encodeURIComponent(String(idOrSlug))}?${params}`
    );
  },
  models: (options: {
    cursor?: string | null;
    limit?: number;
    creator_slug?: string;
    tag?: string;
    has_cover?: boolean;
    cover_status?: string;
    uploaded_by?: string;
  } = {}) => {
    const params = new URLSearchParams({ limit: String(options.limit ?? 48) });
    if (options.cursor) params.set("cursor", options.cursor);
    if (options.creator_slug) params.set("creator_slug", options.creator_slug);
    if (options.tag) params.set("tag", options.tag);
    if (options.has_cover === true || options.has_cover === false) {
      params.set("has_cover", String(options.has_cover));
    }
    if (options.cover_status) params.set("cover_status", options.cover_status);
    if (options.uploaded_by) params.set("uploaded_by", options.uploaded_by);
    return request<{ models: ModelCard[]; next_cursor: number | null }>(`/models?${params}`);
  },
  model: (id: string | number, signal?: AbortSignal) =>
    request<{ model: ModelDetail }>(`/models/${id}`, { signal }),
  likeModel: (id: number) => request<{ model: ModelDetail; liked: boolean }>(`/models/${id}/like`, { method: "POST" }),
  unlikeModel: (id: number) => request<{ model: ModelDetail; liked: boolean }>(`/models/${id}/like`, { method: "DELETE" }),
  likes: () => request<{ models: ModelCard[] }>("/likes"),
  bookmarkFolders: () => request<{ bookmark_folders: BookmarkFolder[] }>("/bookmark_folders"),
  bookmarkFolder: (id: number) => request<{ bookmark_folder: BookmarkFolder }>(`/bookmark_folders/${id}`),
  createBookmarkFolder: (name: string) =>
    request<{ bookmark_folder: BookmarkFolder }>("/bookmark_folders", {
      method: "POST",
      body: JSON.stringify({ name })
    }),
  updateBookmarkFolder: (id: number, payload: { name?: string; position?: number }) =>
    request<{ bookmark_folder: BookmarkFolder }>(`/bookmark_folders/${id}`, {
      method: "PATCH",
      body: JSON.stringify(payload)
    }),
  deleteBookmarkFolder: (id: number) => request<void>(`/bookmark_folders/${id}`, { method: "DELETE" }),
  addBookmark: (folderId: number, modelId: number) =>
    request<{ bookmark: { id: number; model_id: number; bookmark_folder_id: number }; model: ModelCard }>(
      `/bookmark_folders/${folderId}/bookmarks`,
      { method: "POST", body: JSON.stringify({ model_id: modelId }) }
    ),
  removeBookmark: (folderId: number, modelId: number) =>
    request<{ model: ModelCard }>(`/bookmark_folders/${folderId}/bookmarks/${modelId}`, { method: "DELETE" }),
  mergeModels: (payload: {
    library_id: number;
    source_ids?: number[];
    asset_ids?: number[];
    target_id?: number;
    title?: string;
    folder_name?: string;
  }) =>
    request<{ merge: ModelMerge; model: ModelDetail }>("/models/merge", {
      method: "POST",
      body: JSON.stringify(payload)
    }),
  splitModel: (id: number, mergeId?: number) =>
    request<{ merge: ModelMerge; models: ModelCard[] }>(`/models/${id}/split`, {
      method: "POST",
      body: JSON.stringify(mergeId ? { merge_id: mergeId } : {})
    }),
  duplicates: (libraryId?: number, status?: DuplicateStatus | "") => {
    const params = new URLSearchParams();
    if (libraryId) params.set("library_id", String(libraryId));
    if (status) params.set("status", status);
    const suffix = params.toString() ? `?${params}` : "";
    return request<DuplicatesPayload>(`/duplicates${suffix}`);
  },
  analyzeDuplicates: (libraryId: number) =>
    request<{ queued: boolean; library_id: number }>(`/libraries/${libraryId}/duplicates/analyze`, { method: "POST" }),
  keepDuplicate: (id: number) =>
    request<{ group: DuplicateGroup; review: DuplicateReview }>(`/duplicates/${id}/keep`, { method: "POST" }),
  dismissDuplicate: (id: number) =>
    request<{ group: DuplicateGroup; review: DuplicateReview }>(`/duplicates/${id}/dismiss`, { method: "POST" }),
  mergeDuplicate: (
    id: number,
    payload: { source_ids?: number[]; asset_ids?: number[]; target_id?: number; title?: string }
  ) =>
    request<{ group: DuplicateGroup; review: DuplicateReview; merge: ModelMerge; model: ModelDetail }>(
      `/duplicates/${id}/merge`,
      { method: "POST", body: JSON.stringify(payload) }
    ),
  extractDuplicate: (id: number, payload: ArchiveExtractRequest = {}) =>
    request<ArchiveExtractPayload>(`/duplicates/${id}/extract`, {
      method: "POST",
      body: JSON.stringify(payload)
    }),
  extractAndMergeDuplicate: (id: number, payload: ArchiveExtractRequest = {}) =>
    request<ArchiveExtractPayload>(`/duplicates/${id}/extract_and_merge`, {
      method: "POST",
      body: JSON.stringify(payload)
    }),
  archiveMembers: (
    modelId: string | number,
    options: {
      asset_id?: number;
      prefix?: string;
      q?: string;
      view?: "tree" | "flat" | "search";
      limit?: number;
      offset?: number;
      signal?: AbortSignal;
    } = {}
  ) => {
    const params = new URLSearchParams();
    if (options.asset_id != null) params.set("asset_id", String(options.asset_id));
    if (options.prefix != null) params.set("prefix", options.prefix);
    if (options.q) params.set("q", options.q);
    if (options.view) params.set("view", options.view);
    if (options.limit != null) params.set("limit", String(options.limit));
    if (options.offset != null) params.set("offset", String(options.offset));
    const suffix = params.toString() ? `?${params}` : "";
    return request<ArchiveTreeResponse>(`/models/${modelId}/archive_members${suffix}`, {
      signal: options.signal
    });
  },
  archiveMember: (id: number, signal?: AbortSignal) =>
    request<{ member: ArchiveMemberDetail }>(`/archive_members/${id}`, { signal }),
  search: (options: {
    q?: string;
    tag?: string;
    has_preview?: boolean | "";
    creator_slug?: string;
    has_cover?: boolean;
    cover_status?: string;
    uploaded_by?: string;
    offset?: number;
    limit?: number;
    library_id?: number | string;
  }) => {
    const params = new URLSearchParams();
    if (options.q) params.set("q", options.q);
    if (options.tag) params.set("tag", options.tag);
    if (options.has_preview === true || options.has_preview === false) {
      params.set("has_preview", String(options.has_preview));
    }
    if (options.creator_slug) params.set("creator_slug", options.creator_slug);
    if (options.has_cover === true || options.has_cover === false) {
      params.set("has_cover", String(options.has_cover));
    }
    if (options.cover_status) params.set("cover_status", options.cover_status);
    if (options.uploaded_by) params.set("uploaded_by", options.uploaded_by);
    if (options.offset != null) params.set("offset", String(options.offset));
    if (options.limit != null) params.set("limit", String(options.limit));
    if (options.library_id) params.set("library_id", String(options.library_id));
    return request<{
      models: ModelCard[];
      engine: string;
      fallback: boolean;
      capped?: boolean;
      next_offset: number | null;
      estimated_total: number;
      facets: {
        tags: Record<string, number>;
        has_preview?: Record<string, number>;
        creator_slug?: Record<string, number>;
        cover_status?: Record<string, number>;
        has_cover?: Record<string, number>;
      };
    }>(`/search?${params}`);
  },
  proposals: (status?: string) => {
    const suffix = status ? `?status=${encodeURIComponent(status)}` : "";
    return request<{
      proposals: CurationProposal[];
      libraries?: Array<{ id: number; name: string; curation?: CurationPollStatus }>;
    }>(`/curation_proposals${suffix}`);
  },
  approveProposal: (id: number) =>
    request<{ proposal: CurationProposal }>(`/curation_proposals/${id}/approve`, { method: "POST" }),
  rejectProposal: (id: number) =>
    request<{ proposal: CurationProposal }>(`/curation_proposals/${id}/reject`, { method: "POST" }),
  fetchProposals: (libraryId: number) =>
    request<{ proposals: CurationProposal[]; curation?: CurationPollStatus }>("/curation_proposals/fetch", {
      method: "POST",
      body: JSON.stringify({ library_id: libraryId })
    }),
  curatorSettings: async () => {
    const payload = await request<unknown>("/curator_settings");
    return { curator_setting: parseCuratorSetting(payload) };
  },
  updateCuratorSettings: async (payload: {
    provider: CuratorProvider;
    ollama_url?: string | null;
    ollama_model?: string | null;
  }) => {
    const body = await request<unknown>("/curator_settings", {
      method: "PATCH",
      body: JSON.stringify({
        provider: payload.provider,
        ollama_url: payload.ollama_url ?? null,
        ollama_model: payload.ollama_model ?? null
      })
    });
    return { curator_setting: parseCuratorSetting(body) };
  },
  setCuratorApiKey: async (provider: CuratorKeyProvider, apiKey: string) => {
    const body = await request<unknown>(curatorKeyEndpoint(provider), {
      method: "PUT",
      body: JSON.stringify(curatorKeyPutBody(provider, apiKey))
    });
    return { curator_setting: parseCuratorSetting(body) };
  },
  clearCuratorApiKey: async (provider: CuratorKeyProvider) => {
    const body = await request<unknown>(curatorKeyEndpoint(provider), { method: "DELETE" });
    return { curator_setting: parseCuratorSetting(body) };
  },
  bulkProposals: (ids: number[], action: "approve" | "reject") =>
    request<{ proposals: CurationProposal[] }>("/curation_proposals/bulk", {
      method: "POST",
      body: JSON.stringify({ ids, decision: action })
    }),
  printers: () => request<{ printers: Printer[] }>("/printers"),
  createPrinter: (payload: {
    library_id: number;
    name: string;
    host: string;
    protocol_type: string;
    enabled?: boolean;
    notes?: string;
    settings?: Record<string, unknown>;
  }) => request<{ printer: Printer }>("/printers", { method: "POST", body: JSON.stringify(payload) }),
  updatePrinter: (
    id: number,
    payload: Partial<{
      name: string;
      host: string;
      protocol_type: string;
      enabled: boolean;
      notes: string;
      settings: Record<string, unknown>;
    }>
  ) => request<{ printer: Printer }>(`/printers/${id}`, { method: "PATCH", body: JSON.stringify(payload) }),
  deletePrinter: (id: number) => request<void>(`/printers/${id}`, { method: "DELETE" }),
  printJobs: (status?: string) => {
    const suffix = status ? `?status=${encodeURIComponent(status)}` : "";
    return request<{ print_jobs: PrintJob[] }>(`/print_jobs${suffix}`);
  },
  printJob: (id: number) => request<{ print_job: PrintJob }>(`/print_jobs/${id}`),
  print: (modelId: number, printerId: number, assetId?: number) =>
    request<{ print_job: PrintJob }>("/print_jobs", {
      method: "POST",
      body: JSON.stringify({ model_id: modelId, printer_id: printerId, asset_id: assetId })
    }),
  cancelPrint: (id: number) => request<{ print_job: PrintJob }>(`/print_jobs/${id}/cancel`, { method: "POST" }),
  retryPrint: (id: number) => request<{ print_job: PrintJob }>(`/print_jobs/${id}/retry`, { method: "POST" }),
  invites: () => request<{ invites: Invite[] }>("/invites"),
  createInvite: (payload: { library_id: number; email?: string; role?: string; expires_in_days?: number | "" }) =>
    request<{ invite: Invite }>("/invites", {
      method: "POST",
      body: JSON.stringify(payload)
    }),
  previewInvite: (inviteToken: string) => request<{ invite: Invite }>(`/invites/token/${inviteToken}`),
  redeemInvite: (inviteToken: string, payload: { email: string; password: string; display_name: string }) =>
    request<{ token: string; user: User }>(`/invites/${inviteToken}/redeem`, {
      method: "POST",
      body: JSON.stringify(payload)
    }),
  revokeInvite: (id: number) => request<{ invite: Invite }>(`/invites/${id}/revoke`, { method: "POST" }),
  createUpload: (payload: {
    library_id: number;
    folder_name: string;
    relative_path: string;
    filename: string;
    byte_size: number;
  }) => request<{ upload: LibraryUpload }>("/uploads", { method: "POST", body: JSON.stringify(payload) }),
  completeUpload: (id: number) => request<{ upload: LibraryUpload }>(`/uploads/${id}/complete`, { method: "POST" }),
  patchUpload: async (id: number, chunk: Blob, offset: number) => {
    const headers = new Headers();
    headers.set("Accept", "application/json");
    headers.set("Content-Type", "application/offset+octet-stream");
    headers.set("Upload-Offset", String(offset));
    const current = token();
    if (current) headers.set("Authorization", `Bearer ${current}`);
    const response = await fetch(`${API_BASE}/uploads/${id}`, { method: "PATCH", headers, body: chunk });
    const data = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(data.error || `Request failed (${response.status})`);
    return data as { upload: LibraryUpload };
  },
  assetContentUrl: (assetId: number) => `${API_BASE}/assets/${assetId}/content`,
  // Stream-one member bytes. Abort the fetch on navigate-away (MeshViewer + worker terminate).
  // Supports Range: bytes=start-end (206). Mesh preview is this URL, not /preview.
  archiveMemberContentUrl: (id: number, download = false) =>
    `${API_BASE}/archive_members/${id}/content${download ? "?download=1" : ""}`,
  // Derived thumb or inline image. Mesh members return 422 { error: "use_content", content_path }.
  archiveMemberPreviewUrl: (id: number) => `${API_BASE}/archive_members/${id}/preview`
};

export function resolveApiUrl(path: string | null | undefined, fallback: string): string {
  const value = path?.trim();
  if (!value) return fallback;
  if (/^https?:\/\//i.test(value) || value.startsWith("blob:") || value.startsWith("data:")) return value;
  if (API_BASE.startsWith("http")) {
    try {
      return new URL(value, new URL(API_BASE).origin).toString();
    } catch {
      return value;
    }
  }
  return value.startsWith("/") ? value : `/${value}`;
}

export function memberContentUrl(
  member: Pick<ArchiveMember, "id" | "content_path">,
  download = false
): string | null {
  if (!member.id && !member.content_path) return null;
  const fallback = member.id ? api.archiveMemberContentUrl(member.id, download) : "";
  const url = resolveApiUrl(member.content_path, fallback);
  if (!url) return null;
  if (download && !/[?&]download=/.test(url)) return url.includes("?") ? `${url}&download=1` : `${url}?download=1`;
  return url;
}

export function memberPreviewUrl(member: Pick<ArchiveMember, "id" | "preview_path">): string | null {
  if (!member.id && !member.preview_path) return null;
  const fallback = member.id ? api.archiveMemberPreviewUrl(member.id) : "";
  return resolveApiUrl(member.preview_path, fallback) || null;
}

function throwFromFailedResponse(response: Response, data: Record<string, unknown>): never {
  const code = typeof data.error === "string" ? data.error : "";
  const details = Array.isArray(data.details) ? data.details.filter(Boolean).join(" ") : "";
  const message =
    details || (typeof data.message === "string" && data.message) || code || `Request failed (${response.status})`;
  throw new ApiError(message, response.status, code, data);
}

async function readErrorPayload(response: Response): Promise<Record<string, unknown>> {
  const contentType = response.headers.get("Content-Type") || "";
  if (contentType.includes("json")) {
    const data = await response.json().catch(() => ({}));
    return data && typeof data === "object" ? (data as Record<string, unknown>) : {};
  }
  await response.arrayBuffer().catch(() => undefined);
  return {};
}

export async function fetchAuthedBlob(url: string, init: RequestInit = {}): Promise<Blob> {
  const current = token();
  const headers = new Headers(init.headers);
  if (current && !headers.has("Authorization")) headers.set("Authorization", `Bearer ${current}`);
  const response = await fetch(url, { ...init, headers });
  if (!response.ok) throwFromFailedResponse(response, await readErrorPayload(response));
  return response.blob();
}

export async function fetchAuthedBytes(
  url: string,
  init: RequestInit & { onProgress?: (loaded: number, total: number | null) => void; maxBytes?: number } = {}
): Promise<ArrayBuffer> {
  const { onProgress, maxBytes, ...rest } = init;
  const current = token();
  const headers = new Headers(rest.headers);
  if (current && !headers.has("Authorization")) headers.set("Authorization", `Bearer ${current}`);
  const response = await fetch(url, { ...rest, headers });
  if (!response.ok) throwFromFailedResponse(response, await readErrorPayload(response));

  const totalHeader = Number(response.headers.get("Content-Length"));
  const total = Number.isFinite(totalHeader) && totalHeader > 0 ? totalHeader : null;
  if (maxBytes && maxBytes > 0 && total != null && total > maxBytes) {
    await response.body?.cancel().catch(() => undefined);
    throw new ApiError("Refusing to load oversized mesh", 422, "oversized");
  }
  if (!response.body) {
    const buffer = await response.arrayBuffer();
    if (maxBytes && maxBytes > 0 && buffer.byteLength > maxBytes) {
      throw new ApiError("Refusing to load oversized mesh", 422, "oversized");
    }
    onProgress?.(buffer.byteLength, total ?? buffer.byteLength);
    return buffer;
  }

  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let loaded = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    chunks.push(value);
    loaded += value.byteLength;
    if (maxBytes && maxBytes > 0 && loaded > maxBytes) {
      await reader.cancel().catch(() => undefined);
      throw new ApiError("Refusing to load oversized mesh", 422, "oversized");
    }
    onProgress?.(loaded, total);
  }

  const out = new Uint8Array(loaded);
  let offset = 0;
  for (const chunk of chunks) {
    out.set(chunk, offset);
    offset += chunk.byteLength;
  }
  onProgress?.(loaded, total ?? loaded);
  return out.buffer;
}

export async function fetchMemberPreview(url: string, init: RequestInit = {}): Promise<Blob> {
  try {
    return await fetchAuthedBlob(url, init);
  } catch (err) {
    if (err instanceof ApiError && err.code === "use_content") {
      const contentPath = typeof err.data.content_path === "string" ? err.data.content_path : "";
      if (contentPath) return fetchAuthedBlob(resolveApiUrl(contentPath, contentPath), init);
    }
    throw err;
  }
}

export function isAbortError(error: unknown): boolean {
  return (
    (error instanceof DOMException && error.name === "AbortError") ||
    (error instanceof Error && error.name === "AbortError")
  );
}

export const CHUNK_SIZE = 1024 * 1024;

export async function uploadFileResumable(options: {
  libraryId: number;
  folderName: string;
  file: File;
  relativePath: string;
  onProgress?: (ratio: number) => void;
}): Promise<LibraryUpload> {
  const created = await api.createUpload({
    library_id: options.libraryId,
    folder_name: options.folderName,
    relative_path: options.relativePath,
    filename: options.file.name,
    byte_size: options.file.size
  });

  let upload = created.upload;
  let offset = upload.byte_offset;
  while (offset < options.file.size) {
    const blob = options.file.slice(offset, offset + CHUNK_SIZE);
    const patched = await api.patchUpload(upload.id, blob, offset);
    upload = patched.upload;
    offset = upload.byte_offset;
    options.onProgress?.(options.file.size === 0 ? 1 : offset / options.file.size);
  }

  if (upload.status !== "completed") {
    upload = (await api.completeUpload(upload.id)).upload;
  }
  options.onProgress?.(1);
  return upload;
}
