/** API / catalog payload types. Client lives in `api.ts` (see docs/thin-cut-audit.md). */

export type {
  ApiKeyStatus,
  CuratorKeyProvider,
  CuratorProvider,
  CuratorSetting
} from "./curatorSettings";

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

/** Library membership row for the Friend picker — not a Creator. */
export type LibraryMember = {
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
  cover_lqip_url?: string | null;
  cover_placeholder?: boolean;
  // Optional gallery hint. Only render when Backend sets this — do not invent it.
  in_archive?: boolean;
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
  cover_lqip_url?: string | null;
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
  cover_lqip_url?: string | null;
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

export type ExtractedArchiveAsset = {
  archive_member_id: number;
  asset_id: number;
  model_id: number;
  relative_path: string;
  filename: string;
  mergeable: boolean;
  archive_path?: string | null;
};

export type ArchiveExtractPayload = {
  model: ModelDetail;
  assets: ExtractedArchiveAsset[];
  extracted: ExtractedArchiveAsset[];
  merge?: ModelMerge | null;
  group?: DuplicateGroup;
  review?: DuplicateReview;
};

export type ArchiveExtractRequest = {
  archive_member_ids?: number[];
  archive_member_id?: number;
  library_id?: number;
  target_model_id?: number;
  target_id?: number;
  title?: string;
  folder_name?: string;
  source_ids?: number[];
  asset_ids?: number[];
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
  content_path?: string | null;
  preview_path?: string | null;
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
  retryable?: boolean;
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
  last_error?: string | null;
  disabled_reason?: string | null;
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
  queue?: string;
  concurrency?: number;
  worker_concurrency?: number;
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
