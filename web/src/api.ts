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
  libraries: MembershipInfo[];
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

export type CurationProposal = {
  id: number;
  library_id: number;
  kind: string;
  status: string;
  summary: string;
  payload: Record<string, unknown>;
  sidecar_ref: string | null;
  reviewed_at: string | null;
  created_at: string;
};

export type PrintJob = {
  id: number;
  model_id: number;
  asset_id: number | null;
  status: string;
  printer_hint: string | null;
  note: string | null;
  created_at: string;
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
  if (init.body && !(init.body instanceof FormData)) {
    headers.set("Content-Type", "application/json");
  }
  const current = token();
  if (current) headers.set("Authorization", `Bearer ${current}`);

  const response = await fetch(`${API_BASE}${path}`, { ...init, headers });
  if (response.status === 204) return undefined as T;
  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    const message = data.error || `Request failed (${response.status})`;
    throw new Error(message);
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
  models: (cursor?: string | null, limit = 18) => {
    const params = new URLSearchParams({ limit: String(limit) });
    if (cursor) params.set("cursor", cursor);
    return request<{ models: ModelCard[]; next_cursor: number | null }>(`/models?${params}`);
  },
  model: (id: string | number) => request<{ model: ModelDetail }>(`/models/${id}`),
  archiveMembers: (modelId: string | number) =>
    request<{ members: ArchiveMember[] }>(`/models/${modelId}/archive_members`),
  search: (q: string) => request<{ models: ModelCard[]; engine: string }>(`/search?q=${encodeURIComponent(q)}`),
  proposals: (status?: string) => {
    const suffix = status ? `?status=${encodeURIComponent(status)}` : "";
    return request<{ proposals: CurationProposal[] }>(`/curation_proposals${suffix}`);
  },
  approveProposal: (id: number) =>
    request<{ proposal: CurationProposal }>(`/curation_proposals/${id}/approve`, { method: "POST" }),
  rejectProposal: (id: number) =>
    request<{ proposal: CurationProposal }>(`/curation_proposals/${id}/reject`, { method: "POST" }),
  print: (modelId: number, assetId?: number) =>
    request<{ print_job: PrintJob }>("/print_jobs", {
      method: "POST",
      body: JSON.stringify({ model_id: modelId, asset_id: assetId, printer_hint: "browser-bridge" })
    }),
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
