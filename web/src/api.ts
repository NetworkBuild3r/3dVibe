import { parseCuratorSetting, type CuratorProvider } from "./curatorSettings";

const API_BASE = import.meta.env.VITE_API_BASE_URL || "/api/v1";

export type { CuratorProvider, CuratorSetting, XaiApiKeyStatus } from "./curatorSettings";

export type CurationPollStatus = {
  last_polled_at: string | null;
  last_provider: string | null;
  last_error: string | null;
};

export type MembershipInfo = {
  id: number;
  name: string;
  role: string;
  curation?: CurationPollStatus;
};

export type User = {
  id: number;
  email: string;
  display_name: string;
  role: string;
  can_invite: boolean;
  can_upload: boolean;
  can_curate: boolean;
  can_print: boolean;
  can_merge?: boolean;
  can_manage_printers: boolean;
  can_manage_libraries?: boolean;
  libraries: MembershipInfo[];
};

export type Author = {
  id: number;
  display_name: string;
};

export type CoverStatus = "missing" | "pending" | "ready" | "failed";

export type CreatorRef = {
  id: number;
  slug: string;
  name: string;
};

export type Creator = CreatorRef & {
  source?: string | null;
  model_count?: number;
};

export type ModelCard = {
  id: number;
  title: string;
  folder_name: string;
  synopsis: string | null;
  asset_count: number;
  byte_size: number;
  library_id: number;
  library_name: string;
  tags: string[];
  updated_at: string;
  uploaded_by?: Author | null;
  has_preview?: boolean;
  liked?: boolean;
  like_count?: number;
  bookmark_folder_ids?: number[];
  merged?: boolean;
  creator?: CreatorRef | null;
  cover_status?: CoverStatus;
  cover_url?: string | null;
  cover_placeholder?: boolean;
};

export type BookmarkFolder = {
  id: number;
  name: string;
  position: number;
  bookmark_count: number;
  models?: ModelCard[];
  created_at: string;
  updated_at: string;
};

export type ModelMerge = {
  id: number;
  library_id: number;
  target_model_id: number;
  target_title?: string;
  kind: string;
  parts: Array<Record<string, unknown>>;
  result: Record<string, unknown>;
  split_at: string | null;
  performed_by?: Author | null;
  created_at: string;
};

export type DuplicateConfidence = "exact" | "geometry" | "likely";
export type DuplicateReason = "content_hash" | "geometry" | "name_size";
export type DuplicateStatus = "open" | "kept" | "dismissed" | "merged";

export type DuplicateMemberKind = "asset" | "archive_member";

export type DuplicateMember = {
  kind: DuplicateMemberKind | string;
  mergeable: boolean;
  id: number;
  asset_id?: number | null;
  archive_member_id?: number | null;
  filename: string;
  relative_path?: string | null;
  member_path?: string | null;
  archive_path?: string | null;
  parent_asset_id?: number | null;
  parent_filename?: string | null;
  file_kind?: string | null;
  byte_size?: number | null;
  content_digest?: string | null;
  geometry_digest?: string | null;
  model_id: number;
  model_title: string;
  folder_name?: string;
  cover_status?: CoverStatus;
  cover_url?: string | null;
  cover_placeholder?: boolean;
};

export type DuplicateAsset = {
  id: number;
  filename: string;
  relative_path: string;
  kind: string;
  byte_size: number;
  content_digest: string | null;
  geometry_digest?: string | null;
  mergeable?: boolean;
  model_id: number;
  model_title: string;
  folder_name: string;
  cover_status?: CoverStatus;
  cover_url?: string | null;
  cover_placeholder?: boolean;
};

export type DuplicateReview = {
  id: number;
  duplicate_group_id: number;
  user_id: number;
  decision: "keep" | "dismiss" | "merge";
  payload: Record<string, unknown>;
  created_at: string;
};

export type DuplicateGroup = {
  id: number;
  library_id?: number;
  reason: DuplicateReason | string;
  confidence: DuplicateConfidence | string;
  digest: string | null;
  status: DuplicateStatus | string;
  filename: string;
  byte_size: number;
  members?: DuplicateMember[];
  assets: DuplicateAsset[];
  models?: ModelCard[];
  created_at?: string;
  updated_at?: string;
};

export type DuplicatesPayload = {
  library_id: number;
  group_count: number;
  groups: DuplicateGroup[];
};

export type Asset = {
  id: number;
  filename: string;
  relative_path: string;
  kind: string;
  byte_size: number;
  content_digest: string | null;
  archive: boolean;
  mesh: boolean;
  archive_member_count: number;
  archive_truncated?: boolean;
  archive_support?: string | null;
  uploaded_by?: Author | null;
};

export type ModelDetail = ModelCard & {
  folder_mtime: string | null;
  assets: Asset[];
  merges?: ModelMerge[];
};

export type ArchiveMember = {
  id: number | null;
  asset_id: number;
  internal_path: string;
  name: string;
  path: string;
  parent_path: string;
  directory: boolean;
  compressed_size: number | null;
  uncompressed_size: number | null;
  content_type: string | null;
  previewable: boolean;
  has_preview: boolean;
  mesh: boolean;
  image: boolean;
  streamable: boolean;
  accept_ranges?: boolean;
  extension: string;
  listing_source: string | null;
  child_count: number | null;
  has_children: boolean;
};

export type ArchiveSummary = {
  asset_id: number;
  filename: string;
  kind: string;
  member_count: number;
  truncated: boolean;
  support: string | null;
};

export type ArchiveTreeResponse = {
  model_id: number;
  view: "tree" | "flat" | "search";
  prefix?: string;
  q?: string;
  archives: ArchiveSummary[];
  nodes: ArchiveMember[];
  members: ArchiveMember[];
  next_offset: number | null;
  estimated_total: number;
  truncated?: boolean;
};

export type ArchiveMemberDetail = ArchiveMember & {
  model_id: number;
  asset_filename: string;
  asset_kind: string;
  archive_support: string | null;
  mtime: string | null;
  stream_max_bytes?: number;
  stream_max_seconds?: number;
  content_path?: string | null;
  preview_path?: string | null;
};

export type CurationTarget = {
  id: number;
  title: string;
  folder_name: string;
  tags: string[];
  asset_count: number;
};

export type CurationPreview = {
  filesystem: boolean;
  targets: CurationTarget[];
  before: {
    model_id?: number;
    title?: string;
    folder_name?: string;
    tags?: string[];
  };
  after: {
    title?: string;
    folder_name?: string;
    tags?: string[];
    merge_from?: string;
  };
};

export type CurationProposal = {
  id: number;
  library_id: number;
  kind: string;
  status: string;
  summary: string;
  payload: Record<string, unknown>;
  sidecar_ref: string | null;
  rationale?: string | null;
  reason?: string | null;
  explanation?: string | null;
  confidence?: number | string | null;
  reviewed_at: string | null;
  reviewed_by_id: number | null;
  applied_at: string | null;
  apply_error: string | null;
  result: Record<string, unknown>;
  preview: CurationPreview;
  created_at: string;
};

export type PrintJob = {
  id: number;
  library_id: number | null;
  printer_id: number | null;
  printer_name: string | null;
  protocol_type: string | null;
  model_id: number | null;
  model_title: string | null;
  asset_id: number | null;
  filename: string | null;
  status: string;
  progress: number;
  printer_hint: string | null;
  note: string | null;
  error_message: string | null;
  remote_ref: string | null;
  requested_by?: Author | null;
  started_at: string | null;
  finished_at: string | null;
  created_at: string;
  updated_at: string;
};

export type Printer = {
  id: number;
  library_id: number;
  library_name: string;
  name: string;
  host: string;
  protocol_type: string;
  enabled: boolean;
  notes: string | null;
  settings: Record<string, unknown>;
  created_at: string;
  updated_at: string;
};

export type Invite = {
  id: number;
  library_id: number;
  library_name: string;
  email: string | null;
  role: string;
  token?: string;
  redeem_path?: string;
  pending: boolean;
  expires_at: string | null;
  redeemed_at: string | null;
  revoked_at: string | null;
};

export type ScanBudgets = {
  max_seconds?: number;
  max_files?: number;
  max_folders?: number;
};

export type ScanResume = {
  resume_after?: string | null;
  path_prefix?: string | null;
  resume_relative_path?: string | null;
};

export type ScanStatus = {
  id?: number;
  status: string;
  trigger?: string;
  phase?: string;
  path_prefix?: string | null;
  started_at?: string | null;
  finished_at?: string | null;
  resume_after?: string | null;
  folders_seen?: number;
  folders_indexed?: number;
  folders_skipped?: number;
  files_seen?: number;
  files_changed?: number;
  pruned_count?: number;
  error_count?: number;
  deep_walks?: number;
  budget_exhausted?: boolean;
  last_error?: string | null;
  budgets?: ScanBudgets;
  resume?: ScanResume | null;
  updated_at?: string;
};

export type LibraryScanDetail = {
  library_id: number;
  scan: ScanStatus;
  current: ScanStatus | null;
  last: ScanStatus | null;
};

export type MeiliHealth = {
  status: "up" | "down" | "unset" | string;
  configured?: boolean;
  last_error?: string | null;
};

export type CoverBacklog = {
  pending: number;
  failed: number;
  missing: number;
};

export type GeometryBacklog = {
  assets_missing: number;
  archive_members_missing: number;
};

export type OpsSnapshot = {
  library_id: number;
  library_name: string;
  scan: ScanStatus;
  curator: CurationPollStatus;
  covers: CoverBacklog;
  geometry: GeometryBacklog;
  meili: MeiliHealth;
};

export type ScanSettings = {
  max_seconds: number;
  max_files: number;
  max_folders: number;
  prune_batch: number;
  deep_interval: number;
  trust_dir_mtime: boolean;
  allow_empty_prune: boolean;
  schedule: boolean;
  cron: string;
};

export type ScanCursorInfo = {
  path_prefix: string;
  last_mtime: string | null;
  last_byte_size: number | null;
  last_inode: number | null;
  last_nlink: number | null;
  last_dir_mtime: string | null;
  last_file_count: number | null;
  last_scanned_at: string | null;
  last_deep_scanned_at: string | null;
  resume_relative_path: string | null;
};

export type LibraryInfo = {
  id: number;
  name: string;
  root_path: string;
  notes: string | null;
  model_count: number;
  shared: boolean;
  role: string;
  can_upload: boolean;
  can_print: boolean;
  can_merge?: boolean;
  can_manage_printers: boolean;
  can_scan?: boolean;
  scan?: ScanStatus;
  scan_settings?: ScanSettings;
  cursors?: ScanCursorInfo[];
  curation?: CurationPollStatus;
};

export type LibraryUpload = {
  id: number;
  library_id: number;
  folder_name: string;
  relative_path: string;
  filename: string;
  byte_size: number;
  byte_offset: number;
  status: string;
  completed_at: string | null;
};

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
  libraryScan: (id: number | string) => request<LibraryScanDetail>(`/libraries/${id}/scan`),
  libraryOps: (id: number | string) => request<{ ops: OpsSnapshot }>(`/libraries/${id}/ops`),
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
  models: (cursor?: string | null, limit = 18) => {
    const params = new URLSearchParams({ limit: String(limit) });
    if (cursor) params.set("cursor", cursor);
    return request<{ models: ModelCard[]; next_cursor: number | null }>(`/models?${params}`);
  },
  model: (id: string | number) => request<{ model: ModelDetail }>(`/models/${id}`),
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
  archiveMembers: (
    modelId: string | number,
    options: {
      asset_id?: number;
      prefix?: string;
      q?: string;
      view?: "tree" | "flat" | "search";
      limit?: number;
      offset?: number;
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
    return request<ArchiveTreeResponse>(`/models/${modelId}/archive_members${suffix}`);
  },
  archiveMember: (id: number) => request<{ member: ArchiveMemberDetail }>(`/archive_members/${id}`),
  search: (options: {
    q?: string;
    tag?: string;
    has_preview?: boolean | "";
    creator_slug?: string;
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
    if (options.offset != null) params.set("offset", String(options.offset));
    if (options.limit != null) params.set("limit", String(options.limit));
    if (options.library_id) params.set("library_id", String(options.library_id));
    return request<{
      models: ModelCard[];
      engine: string;
      fallback: boolean;
      next_offset: number | null;
      estimated_total: number;
      facets: {
        tags: Record<string, number>;
        has_preview: Record<string, number>;
        creator_slug?: Record<string, number>;
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
  setCuratorXaiApiKey: async (xaiApiKey: string) => {
    const body = await request<unknown>("/curator_settings/xai_api_key", {
      method: "PUT",
      body: JSON.stringify({ xai_api_key: xaiApiKey })
    });
    return { curator_setting: parseCuratorSetting(body) };
  },
  clearCuratorXaiApiKey: async () => {
    const body = await request<unknown>("/curator_settings/xai_api_key", { method: "DELETE" });
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
  }) => request<{ printer: Printer }>("/printers", { method: "POST", body: JSON.stringify(payload) }),
  updatePrinter: (
    id: number,
    payload: Partial<{ name: string; host: string; protocol_type: string; enabled: boolean; notes: string }>
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
  // Stream-one member bytes. Abort the fetch on navigate-away.
  // Supports Range: bytes=start-end (206). Mesh preview is this URL, not /preview.
  archiveMemberContentUrl: (id: number, download = false) =>
    `${API_BASE}/archive_members/${id}/content${download ? "?download=1" : ""}`,
  // Derived thumb or inline image. Mesh members return 422 { error: "use_content", content_path }.
  archiveMemberPreviewUrl: (id: number) => `${API_BASE}/archive_members/${id}/preview`
};

export async function fetchAuthedBlob(url: string, init: RequestInit = {}): Promise<Blob> {
  const current = token();
  const headers = new Headers(init.headers);
  if (current && !headers.has("Authorization")) headers.set("Authorization", `Bearer ${current}`);
  const response = await fetch(url, { ...init, headers });
  if (!response.ok) throw new Error("Could not load file");
  return response.blob();
}

export function isAbortError(error: unknown): boolean {
  return error instanceof DOMException && error.name === "AbortError";
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
