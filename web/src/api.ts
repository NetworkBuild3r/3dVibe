const API_BASE = import.meta.env.VITE_API_BASE_URL || "/api/v1";

export type MembershipInfo = {
  id: number;
  name: string;
  role: string;
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
  can_manage_printers: boolean;
  libraries: MembershipInfo[];
};

export type Author = {
  id: number;
  display_name: string;
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
  uploaded_by?: Author | null;
};

export type ModelDetail = ModelCard & {
  folder_mtime: string | null;
  assets: Asset[];
};

export type ArchiveMember = {
  id: number;
  asset_id: number;
  internal_path: string;
  directory: boolean;
  compressed_size: number | null;
  uncompressed_size: number | null;
  previewable: boolean;
  extension: string;
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
  can_manage_printers: boolean;
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
    throw new Error(data.error || `Request failed (${response.status})`);
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
  models: (cursor?: string | null, limit = 18) => {
    const params = new URLSearchParams({ limit: String(limit) });
    if (cursor) params.set("cursor", cursor);
    return request<{ models: ModelCard[]; next_cursor: number | null }>(`/models?${params}`);
  },
  model: (id: string | number) => request<{ model: ModelDetail }>(`/models/${id}`),
  archiveMembers: (modelId: string | number) =>
    request<{ members: ArchiveMember[] }>(`/models/${modelId}/archive_members`),
  search: (options: {
    q?: string;
    tag?: string;
    has_preview?: boolean | "";
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
    if (options.offset != null) params.set("offset", String(options.offset));
    if (options.limit != null) params.set("limit", String(options.limit));
    if (options.library_id) params.set("library_id", String(options.library_id));
    return request<{
      models: ModelCard[];
      engine: string;
      fallback: boolean;
      next_offset: number | null;
      estimated_total: number;
      facets: { tags: Record<string, number>; has_preview: Record<string, number> };
    }>(`/search?${params}`);
  },
  proposals: (status?: string) => {
    const suffix = status ? `?status=${encodeURIComponent(status)}` : "";
    return request<{ proposals: CurationProposal[] }>(`/curation_proposals${suffix}`);
  },
  approveProposal: (id: number) =>
    request<{ proposal: CurationProposal }>(`/curation_proposals/${id}/approve`, { method: "POST" }),
  rejectProposal: (id: number) =>
    request<{ proposal: CurationProposal }>(`/curation_proposals/${id}/reject`, { method: "POST" }),
  fetchProposals: (libraryId: number) =>
    request<{ proposals: CurationProposal[] }>("/curation_proposals/fetch", {
      method: "POST",
      body: JSON.stringify({ library_id: libraryId })
    }),
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
  assetContentUrl: (assetId: number) => `${API_BASE}/assets/${assetId}/content`
};

export async function fetchAuthedBlob(url: string): Promise<Blob> {
  const current = token();
  const response = await fetch(url, {
    headers: current ? { Authorization: `Bearer ${current}` } : undefined
  });
  if (!response.ok) throw new Error("Could not load mesh");
  return response.blob();
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
