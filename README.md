# 3dvibe

3dvibe is original software for a solo-operated, NFS-backed 3D model and print library. An owner invites friends into **one shared catalog**. This repository is a clean-room implementation — it is not derived from any other 3D library product.

## Shared-by-default

Storage is the owner's NFS mount. There is one library pile.

- Every signed-in user sees every model. There is no per-user hidden folder and no "don't share" toggle.
- Authorship (`uploaded_by`) is stored for audit only. It is never used to hide files.
- Policy: if you do not want it shared, do not upload.

## Roles

| Role | Who | What they can do |
| --- | --- | --- |
| `owner` | The library admin | Invite/revoke, upload, trigger/schedule library scans, review/apply curation, manage printers, **send print jobs** |
| `contributor` | Default for invited friends | Browse/search the whole catalog, upload, like/bookmark, review/apply curation, merge/split models, analyze/review duplicates |
| `viewer` | Optional read-only invite | Browse/search the catalog, like/bookmark, see the curation queue, list duplicate groups |

## What you get

- Rails 8 API (Ruby 3.3 in Docker, 3.2+ on the host) with PostgreSQL, Redis, and Sidekiq
- React + Vite + TypeScript gallery with infinite scroll and a dark Tailwind UI
- Owner invite links (optional email, role, expiry) plus a redeem/signup page
- Chunked, resumable uploads (1 MB patches, TUS-style offset) path-jailed to the library root
- Production NFS library scanning: scheduled + on-demand incremental sync, mtime/size/inode cursors, per-job budgets with resume, batched prune, owner-visible scan status
- Deep archive visibility: nested zip/3mf tree, single-member streaming, image thumbs, lazy mesh members
- Token auth
- HITL AI curation: sidecar contract, stub curator, ingest, review queue, path-jailed apply
- Meilisearch-backed faceted search with a Postgres `ILIKE` fallback when Meili is down or unset
- In-browser Three.js viewer that **does not** auto-load meshes on cards
- Print-from-browser: owner printer registry, **owner-only** enqueue, private print history, path-jailed Sidekiq dispatch, mock adapter + SDCP interface
- Personal likes and bookmark folders (organize the shared catalog; they never hide models)
- Path-jailed model merge/split (move archives/STLs on disk, never load them into RAM)
- Duplicate review: persisted groups (exact SHA-256, geometry digest, name+size), HITL keep/dismiss/merge. Near-dups are never auto-deleted.
- Creator-first catalog: scan upserts `Creator` from the first-level folder / pack-style prefixes (`Creator - Title`, known packs). Shared labels only — no private shelves
- Budgeted covers: scan enqueues `GenerateCoverJob` (pending); the worker generates a libvips thumbnail and writes back `ready`/`failed` + `cover_url`

## Architecture

```
web (Vite SPA) ──JSON──► api (Rails 8, API-only)
                              │
                              ├── PostgreSQL   catalog, users, invites, uploads, cursors
                              ├── Redis        Sidekiq
                              ├── Meilisearch  vibe_models index (compose default)
                              └── NFS / disk   library root (bind-mounted, read-write)
```

Domain objects (original names):

| Object | Meaning |
| --- | --- |
| `Library` | Root path on disk (your NFS mount) |
| `VibeModel` | One folder under that root |
| `Asset` | An on-disk file, with a content digest when the file is small enough and an optional `geometry_digest` from `GeometryFingerprint` |
| `ArchiveMember` | An indexed zip/3mf entry. Optional `geometry_digest` (`mesh:v1:…`) written by Rendering — not a second Asset row |
| `DuplicateGroup` | Persisted cluster (`content_hash` / `geometry` / `name_size`) with HITL status `open` \| `kept` \| `dismissed` \| `merged` |
| `DuplicateGroupMember` | Exactly one of `asset_id` or `archive_member_id` in a group |
| `DuplicateReview` | Keep / dismiss / merge decision + payload |
| `Tag` / `TagAssignment` | Lightweight joins for search and display |
| `User` / `Membership` / `Invite` | Owner, contributor, or viewer |
| `LibraryUpload` | Resumable upload session that lands inside the library jail |
| `CurationProposal` | Sidecar suggestion: pending / approved / rejected |
| `ScanCursor` | Incremental NFS fingerprint per folder prefix (mtime, size, inode, nlink, deep-scan time) |
| `ScanRun` | One walk/prune attempt: status, file/folder counts, errors, resume cursor |
| `Printer` | Owner-managed registry entry (name, host/IP, protocol, enabled) |
| `PrintDispatch` | Print job private to the requester: queued → sending → printing → succeeded/failed/cancelled |
| `Like` / `BookmarkFolder` / `Bookmark` | Personal catalog organization (not visibility) |
| `Creator` | Shared label derived from a first-level folder or pack-style prefix (`nfs_hint`). Not a shelf and not per-user |
| `ModelMerge` | Recorded merge so a split can restore first-level folders |

Background jobs:

- `IncrementalScanJob` — incremental NFS walk (or one folder prefix after an upload/curation apply); honors `VIBE_SCAN_*` budgets and re-enqueues when budgeted
- `ScheduledScanJob` — sidekiq-cron entry that queues a scan for every library (default every 6 hours)
- `IndexVibeModelJob` / `RemoveVibeModelIndexJob` / `ReindexSearchJob` — keep Meilisearch in sync after scan, upload, destroy, and curation apply
- `DerivePreviewJob` — copies hot image members out of an archive into a preview cache (mesh rasterization is still a stub)
- `FetchCurationProposalsJob` — polls the curator sidecar (or in-process stub), upserts pending `CurationProposal` rows by stable `sidecar_ref`, and writes per-library `last_polled_at` / `last_provider` / `last_error`
- `ApplyCurationProposalJob` — applies an approved rename/move/merge (tags apply in-request)
- `DispatchPrintJob` — path-jails a library file and sends it through a printer adapter (mock simulates progress)
- `ModelComposer` — merge/split first-level folders and selected files inside the path jail
- `AnalyzeDuplicatesJob` — on-demand (not every NFS poll): size-prefilter, stream SHA-256, upsert `open` groups (loose + archive members on geometry), enqueue geometry fingerprints
- `ComputeGeometryDigestJob` / `GeometryFingerprint` — path-jailed STL/OBJ/3MF fingerprint (`mesh:v1:<sha256>`). Accepts a loose `Asset` or an `ArchiveMember`. Writes via `GeometryWriteback.apply!`. Huge meshes skip / time out; 3MF streams the `.model` member
- `ComputeArchiveMemberGeometryDigestJob` — path-jails the parent zip/7z/rar/3mf, streams **one** mesh member, computes the same `mesh:v1:` digest, writes `archive_members.geometry_digest`
- `DuplicateFinder` / `DuplicateAnalyzer` — cluster by content hash (Asset only), geometry digest (Asset + ArchiveMember), then name+size (Asset); persist only; never delete NFS files
- `GeometryWriteback` — Rendering sets `assets.geometry_digest` or `archive_members.geometry_digest` (`POST /api/v1/geometry/writeback` or `GeometryWriteback.apply!`)
- `GenerateCoverJob` — path-jails the locked cover payload, generates a budgeted libvips webp (or fails for mesh-without-preview), writes back via `CoverWriteback.apply!`
- `CoverEnqueue` / `CoverWriteback` — scan sets `cover_status=pending`; write-back sets `ready`/`failed` + `cover_url`

The curation sidecar is `CurationSidecar`. In development/test a blank or `stub` URL generates deterministic fixture proposals. Compose profile `curator` runs the live HTTP sidecar (`stub` | `ollama` | `xai`) behind the same contract. HITL approve/apply stays in Rails.

## Quick start (Docker Compose)

```bash
cp .env.example .env
docker compose up --build
```

Or: `bin/dev` (uses Compose when Docker is available).

The library bind-mount is **read-write** so contributor uploads can land on disk. Point `VIBE_LIBRARY_HOST_PATH` at your NFS mount for real use.

Services:

| Service | URL |
| --- | --- |
| Web UI | http://localhost:5173 |
| API | http://localhost:3000 |
| API health | http://localhost:3000/up |
| Postgres | localhost:5432 |
| Redis | localhost:6379 |
| Meilisearch | http://localhost:7700 (`MEILI_URL` / `MEILI_MASTER_KEY`) |
| Curator sidecar (optional) | `docker compose --profile curator up` → localhost:8088 (`VIBE_CURATOR_PROVIDER=stub` default) |

On first boot the API runs `db:prepare`. Seed the owner and scan the sample library:

```bash
docker compose exec api bin/rails db:seed
# or rescan / rebuild the search index later
docker compose exec api bin/rails vibe:scan            # incremental; honors VIBE_SCAN_* budgets
docker compose exec api bin/rails vibe:enqueue_scan    # async IncrementalScanJob
docker compose exec api bin/rails vibe:reindex
```

Default owner (override with `VIBE_OWNER_EMAIL` / `VIBE_OWNER_PASSWORD`):

- email: `owner@3dvibe.local`
- password: `vibe-dev-password`

Open the web app, sign in, scroll the gallery, type `hero` (Packed Minis via the member path), open **Packed Minis**, expand `minis.zip`, search within the archive, and load `hero.stl` or `preview/hero.png`. Meshes never auto-load.

Search indexes title, folder path, tags, asset filenames/paths, archive-member paths, uploader, creator name/slug, `updated_at`, and `has_preview` (mesh or previewable archive member). Meilisearch facets/filters `creator_slug` (and still `tags` / `has_preview`). If Meilisearch is unreachable, `GET /api/v1/search` answers from Postgres `ILIKE` (including creator name/slug) and sets `fallback: true`.

### Print from browser (mock printer)

The browser never talks to a printer. It only calls the 3dvibe API. The API/worker reads the file from the library jail and hands it to an adapter.

```bash
docker compose exec api bin/rails db:seed          # seeds a "Studio mock" printer
# Owner: Printers page → add/edit/remove (or keep the seeded mock)
# Owner only: open Signal Horn → Print → job walks queued → succeeded
# Personal history: Prints (other users cannot see this job)
docker compose exec api bin/rails vibe:print       # same path without the UI
```

Likes, shelves, merge/split, and duplicates:

1. Heart a card or open **Shelves** to make a personal folder. The model stays in everyone's library.
2. Owner/contributor: select two cards → **Merge into one model**, then open the result and **Split last merge**.
3. **Duplicates** — owner/contributor **Analyze**, then review persisted groups (Open / Kept / Dismissed / Merged). Keep (intentional copies, still in the catalog), dismiss (not a delete), or merge through `ModelComposer`. Viewers get a read-only compare. Near-dups (`geometry` / `name_size`) stay HITL; nothing is auto-deleted from NFS.

### Invite a friend

1. Sign in as the owner and open **Invites**.
2. Create a link (optional email, role `contributor` or `viewer`, optional expiry).
3. Share `/invite/<token>`. The friend sets a password, is signed in, and sees the whole catalog.

### Upload

1. Contributors (and the owner) open **Upload**.
2. Drop files or a folder. Name the destination folder under the library root.
3. Files upload in 1 MB resumable chunks, then a targeted scan indexes them for everyone.

### HITL curation

1. Sign in as the owner or a contributor and open **Curation**.
2. Click **Refresh proposals** (or `docker compose exec api bin/rails vibe:curate`).
3. Review before/after, then approve, reject, or use bulk actions.
4. Tags write immediately. Rename/move/merge run through `ApplyCurationProposalJob` inside the library path jail, then enqueue a targeted incremental scan.
5. Poll status (`last_polled_at`, `last_provider`, `last_error`) is on Curation, Libraries, and `GET /me`. A success clears a stale error. `last_provider` is the sidecar echo or the effective UI/ENV provider used on that poll. Nothing is auto-approved.
6. Owner-only **Curator** settings (`/settings/curator`, Avatar menu, or **Configure** on the Curation status strip) choose `stub` / `ollama` / `xai` and store an encrypted xAI key. Env vars stay the compose/CI fallback when the UI is unset. The SPA never receives the decrypted key.

```bash
# in-process stub (default in compose: VIBE_CURATOR_URL=stub) — CI path
docker compose exec api bin/rails vibe:curate

# HTTP sidecar (same JSON contract). Provider defaults to stub.
docker compose --profile curator up --build
# set VIBE_CURATOR_URL=http://curator:8088 in .env and restart api/worker

# Ollama on the host (native /api/chat, or OpenAI-compat if URL ends in /v1)
# ollama serve && ollama pull llama3.1
VIBE_CURATOR_URL=http://curator:8088
VIBE_CURATOR_PROVIDER=ollama
VIBE_OLLAMA_URL=http://host.docker.internal:11434
VIBE_OLLAMA_MODEL=llama3.1
VIBE_CURATOR_TIMEOUT=90

# xAI Grok
VIBE_CURATOR_URL=http://curator:8088
VIBE_CURATOR_PROVIDER=xai
XAI_API_KEY=...
XAI_BASE_URL=https://api.x.ai/v1
XAI_MODEL=grok-4
VIBE_CURATOR_TIMEOUT=90
```

Raise Rails `VIBE_CURATOR_TIMEOUT` above `VIBE_CURATOR_INFER_TIMEOUT` (sidecar default 60s) when using a live provider. The sidecar only suggests; nothing is auto-approved.

## Host install (`bin/dev` without Docker)

Needs Ruby 3.2+, Bundler, Node 20+, PostgreSQL, and Redis.

```bash
export DATABASE_URL=postgres://vibe:vibe@127.0.0.1:5432/td_vibe_development
export REDIS_URL=redis://127.0.0.1:6379/0
export VIBE_LIBRARY_ROOT="$PWD/fixtures/library"
cd api && bundle install && bin/rails db:prepare && bin/rails db:seed
cd ../web && npm install
../bin/dev
```

`VIBE_LIBRARY_ROOT` must be writable by the API process if you want uploads.

## NFS mount

3dvibe never mounts NFS itself. Mount on the host (or NAS appliance), then point the app at that path.

```bash
# host example — adjust server/export/options
sudo mount -t nfs -o "$VIBE_NFS_MOUNT_OPTIONS" \
  "${VIBE_NFS_SERVER}:${VIBE_NFS_EXPORT}" \
  "$VIBE_LIBRARY_HOST_PATH"
```

Environment variables (see `.env.example`):

| Variable | Role |
| --- | --- |
| `VIBE_LIBRARY_HOST_PATH` | Host path bind-mounted into `api` and `worker` (writable) |
| `VIBE_LIBRARY_ROOT` | Path **inside** those containers (default `/library`) |
| `VIBE_LIBRARY_NAME` | Display name stored on the `Library` row |
| `VIBE_MAX_UPLOAD_BYTES` | Per-file upload cap (default 5 GiB) |
| `VIBE_OWNER_EMAIL` / `VIBE_OWNER_PASSWORD` | Seeded owner account |
| `VIBE_NFS_SERVER` / `VIBE_NFS_EXPORT` / `VIBE_NFS_MOUNT_OPTIONS` | Host-side mount hints only |
| `VIBE_CURATOR_URL` | Curator base URL, or `stub` for the in-process fixture generator (CI default) |
| `VIBE_CURATOR_PROVIDER` | Sidecar adapter (`ollama` \| `xai` \| `stub`) when owner UI is unset. Rails also sends it as catalog `provider_hint` and `curator_runtime.provider`. Does **not** replace the URL. |
| `VIBE_ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` | Active Record encryption primary key (compose/CI). Or Rails credentials `active_record_encryption.primary_key`. |
| `VIBE_ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY` | Encryption deterministic key (compose/CI). Or credentials `active_record_encryption.deterministic_key`. |
| `VIBE_ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` | Encryption key-derivation salt (compose/CI). Or credentials `active_record_encryption.key_derivation_salt`. |
| `VIBE_CURATOR_TOKEN` | Shared bearer token for poll + webhook ingest |
| `VIBE_CURATOR_TIMEOUT` | Rails HTTP poll timeout in seconds (default 8). Raise this for live inference. |
| `VIBE_CURATOR_BATCH_SIZE` | Sidecar proposal budget (default 8, max 50) |
| `VIBE_CURATOR_CATALOG_LIMIT` | Max models sent to a live LLM (default 80; ranked by missing tags/cover) |
| `VIBE_CURATOR_INFER_TIMEOUT` | Sidecar LLM HTTP timeout in seconds (default 60) |
| `VIBE_OLLAMA_URL` | Ollama base (`http://host.docker.internal:11434` or `…/v1` for OpenAI-compat) |
| `VIBE_OLLAMA_MODEL` | Ollama model (default `llama3.1`) |
| `VIBE_OLLAMA_API` | `openai` or `native` (blank = native unless URL ends in `/v1`) |
| `XAI_API_KEY` | xAI API key (`VIBE_XAI_API_KEY` alias) |
| `XAI_BASE_URL` | xAI base (default `https://api.x.ai/v1`) |
| `XAI_MODEL` | xAI model (default `grok-4`) |
| `VIBE_PRINT_TIMEOUT` | Adapter timeout in seconds (default 15). Timeouts mark the job failed; they do not 502 the UI |
| `VIBE_PRINT_MOCK_DELAY_MS` | Mock adapter step delay (compose default 400; unset/0 in tests) |
| `MEILI_URL` | Meilisearch base URL (`http://meilisearch:7700` in compose). Alias: `MEILISEARCH_URL` |
| `MEILI_MASTER_KEY` | Admin key used to create the index and write documents |
| `MEILI_SEARCH_KEY` | Optional search-only key. When blank, search uses the master key |
| `MEILI_TIMEOUT` | HTTP timeout in seconds for Meili calls (default 2). Failures fall back to Postgres |
| `VIBE_ARCHIVE_MEMBER_LIMIT` | Max file members indexed per archive (default 10_000). Parents are still synthesized. Excess sets `archive_truncated` |
| `VIBE_ARCHIVE_STREAM_BYTES` | Cap for a single member stream (default 32 MiB). The whole zip is never loaded into RAM |
| `VIBE_ARCHIVE_PREVIEW_BYTES` | Cap for derived/inline image previews (default 4 MiB) |
| `VIBE_ARCHIVE_LIST_TIMEOUT` | Timeout for `7z l` (default 15s) |
| `VIBE_PREVIEW_ROOT` | Directory for derived archive thumbs (default `api/tmp/previews`) |
| `VIBE_COVER_ROOT` | Directory for generated cover webps (default `api/tmp/covers`). Served at `GET /covers/:id.webp` |
| `VIBE_7Z_BIN` | Optional absolute path to `7z` / `7za` |
| `VIBE_SCAN_*` | Incremental NFS scan budgets, cron, and deep-walk interval (see below) |

Each first-level directory under the library root becomes a `VibeModel`. Hidden first-level folders (including `.vibe-incoming` used during uploads) are ignored. Files beneath a model folder become `Asset` rows.

### Incremental NFS scanning

3dvibe **polls** the mount. inotify (or similar) is not used — it is unreliable over NFS and is not required.

`ScheduledScanJob` (sidekiq-cron, `VIBE_SCAN_CRON`, default every 6 hours) and the owner **Scan now** button / `POST /api/v1/libraries/:id/scan` / `bin/rails vibe:scan` all run the same `LibraryScanner` path. Uploads and curation apply still enqueue a **path-prefix** targeted scan and do not prune sibling folders.

**Change detection (cheap, then deep)**

1. List first-level folder names (`Dir.each_child`) — no full-tree walk.
2. `lstat` each model folder. If directory **mtime + inode + nlink** match the `ScanCursor` and a deep walk ran inside `VIBE_SCAN_DEEP_INTERVAL`, the folder is skipped (no file walk).
3. Otherwise walk regular files once (sorted relative paths, no symlink follow). A file is reindexed when **size, mtime, or inode** differs. The cursor then stores the content fingerprint (max file mtime, total bytes, file count) plus the directory identity.

**NFS limitations** (these are why the deep interval exists):

| Quirk | What 3dvibe does |
| --- | --- |
| Attribute cache (`acregmin` / `acdirmin`) can hide a just-written mtime/size | Next poll after the cache expires, or a targeted scan after upload |
| Some NAS boxes do **not** bump the parent directory mtime on in-place overwrite | Mandatory deep walk every `VIBE_SCAN_DEEP_INTERVAL` (default 6h). Set `VIBE_SCAN_TRUST_DIR_MTIME=0` to deep-walk every cycle |
| 1-second mtime resolution; same-second same-size replace | Combined with size + inode. A same-second rewrite that keeps inode and size can still be missed until the next deep walk |
| Inode reuse after delete+create | Identity is inode + mtime + nlink together, not inode alone |
| `ESTALE` / dropped export | Per-folder errors are counted; a root that lists **zero** model folders will **not** prune the catalog unless `VIBE_SCAN_ALLOW_EMPTY_PRUNE=1` |
| Clock skew between NAS and app host | Comparisons use integer-second mtimes stored from `lstat` on the app/worker |

**Budgets and resume.** `VIBE_SCAN_MAX_SECONDS` / `VIBE_SCAN_MAX_FILES` / `VIBE_SCAN_MAX_FOLDERS` stop a job before it OOMs or pins a worker. Progress is stored on `ScanRun.resume_after` (folder) and `ScanCursor.resume_relative_path` (file). A budgeted full scan re-enqueues `IncrementalScanJob`. Prune of disappeared paths runs only after a complete walk, in `VIBE_SCAN_PRUNE_BATCH` batches, then `ReindexSearchJob` refreshes Meilisearch. Destroying a `VibeModel` also removes its Meili document.

Owner API `GET /api/v1/libraries` (and show) includes the latest `scan` object. The **Libraries** page shows last started/finished, files seen, errors, cursors, and a Scan now button.

| Variable | Role |
| --- | --- |
| `VIBE_SCAN_SCHEDULE` | Load sidekiq-cron job (default on). `0` disables |
| `VIBE_SCAN_CRON` | Cron expression (default `0 */6 * * *`) |
| `VIBE_SCAN_MAX_SECONDS` | Wall-clock cap per job (default 120). `0` = unlimited |
| `VIBE_SCAN_MAX_FILES` | Files indexed per job (default 5000). `0` = unlimited |
| `VIBE_SCAN_MAX_FOLDERS` | Folders deep-walked/indexed per job (default 200). `0` = unlimited |
| `VIBE_SCAN_PRUNE_BATCH` | Max disappeared models/cursors removed per job (default 50) |
| `VIBE_SCAN_DEEP_INTERVAL` | Seconds between deep walks of an unchanged folder identity (default 21600) |
| `VIBE_SCAN_TRUST_DIR_MTIME` | Skip deep walk when dir identity is fresh (default 1) |
| `VIBE_SCAN_ALLOW_EMPTY_PRUNE` | Allow wiping the catalog when the mount lists no folders (default 0) |
| `VIBE_COVER_TOKEN` | Shared token for `POST /api/v1/covers/writeback` (`X-Cover-Token` or Bearer). Signed-in users can also write back |
| `VIBE_GEOMETRY_TOKEN` | Shared token for `POST /api/v1/geometry/writeback` (`X-Geometry-Token` or Bearer). Owner/contributor can also write back |
| `VIBE_GEO_MAX_BYTES` | Skip a mesh larger than this many bytes (default 64 MiB). `0` = unlimited |
| `VIBE_GEO_MAX_VERTS` | Skip after this many streamed vertices (default 250000). `0` = unlimited |
| `VIBE_GEO_MAX_SECONDS` | Wall-clock cap per fingerprint (default 20). `0` = unlimited |
| `VIBE_GEO_QUANT` | Vertex quantization grid in model units (default 0.01) |
| `VIBE_GEO_MAX_ASSETS` | Meshes fingerprinted inline per analyze (default 40). `0` = unlimited |
| `VIBE_DUP_MAX_SECONDS` | Wall-clock cap per analyze job (default 60). `0` = unlimited |
| `VIBE_DUP_MAX_FILES` | Streamed hashes per analyze job (default 2000). `0` = unlimited |
| `VIBE_COVER_MAX_PX` | Cover generate budget, pixels (default 512). Passed through on the enqueue payload |
| `VIBE_COVER_MAX_BYTES` | Cover generate budget, bytes (default 250000). Passed through on the enqueue payload |

### Archive visibility

`IncrementalScanJob` → `LibraryScanner` → `ArchiveIndexer`. Members are stored with `parent_path` so the API can return a folder page instead of a flat dump.

| Format | Listing | Single-member stream | Notes |
| --- | --- | --- | --- |
| zip / 3mf | **Full** — central directory only | **Full** — 64 KiB copy into a tempfile, then `send_file` | Default path. Parent folders are synthesized when the zip omits directory entries. |
| 7z / rar | **Best-effort** — `7z l -slt` when `7z` is on PATH | **Best-effort** — `7z e -so` of one path | Compose images install `p7zip-full`. Without the CLI, one `(listing pending)` placeholder is stored and the UI says so. |

The indexer never extracts an archive to disk. A huge listing stops at `VIBE_ARCHIVE_MEMBER_LIMIT` and sets `assets.archive_truncated`. A single member larger than `VIBE_ARCHIVE_STREAM_BYTES` is refused.

`DerivePreviewJob` copies up to 24 hot image members (shallow / names like preview, thumb, cover, hero) into `VIBE_PREVIEW_ROOT`. Mesh members stay lazy: the tree shows a Load action; Three.js only runs after a click.

Search (Meilisearch `archive_paths` and Postgres `ILIKE`) includes file member paths, so `hero` still hits Packed Minis. Directory rows and placeholders are excluded from the search document.

### Creators and budgeted covers

**Creators** are shared labels, not shelves. Scan upserts a `Creator` from the first-level folder name, or from a pack-style prefix (`Creator - Title`, known packs such as Mz4250 / Printable Scenery). `vibe_models.creator_id` is nullable. The heuristic never creates bookmark folders, per-user piles, or federation.

**Covers.** Scan owns enqueue + index fields. `GenerateCoverJob` generates and writes back.

On scan, when a cover-candidate asset appears (image named cover/preview/thumb/hero, else any image, else a loose mesh) or the model is missing a cover, `CoverEnqueue` sets `cover_status=pending` and enqueues `GenerateCoverJob` with this payload (Sidekiq job args — one JSON object):

```json
{
  "library_id": 1,
  "model_id": 42,
  "asset_id": 99,
  "jailed_path": "CreatorPack/model/preview.png",
  "mtime": 1710000000,
  "content_hash": "sha256:…",
  "budget": { "max_px": 512, "max_bytes": 250000 }
}
```

`jailed_path` is jail-relative from the library root. Resolve it with `LibraryPathJail#resolve_jailed` (never load the whole file or archive into RAM). Cache key is `asset_id + mtime + content_hash` (`cover_cache_key` on the model). The same key is not re-enqueued while `pending` or `ready`.

Model card / index fields:

| Field | Values |
| --- | --- |
| `creator` | `{ id, slug, name }` or `null` |
| `cover_status` | `missing` \| `pending` \| `ready` \| `failed` |
| `cover_url` | nullable |
| `cover_placeholder` | bool (`true` until a real cover is written back) |

### Duplicate groups (HITL)

Analyze is on-demand — it is **not** hooked to every NFS poll. `POST /api/v1/libraries/:id/duplicates/analyze` queues `AnalyzeDuplicatesJob`.

The worker size-prefilters (only files that share a byte size are streamed for SHA-256), path-jails every hash (`LibraryPathJail#resolve_file` + `Digest::SHA256.file`), and never loads archives into RAM. Pending loose `stl` / `obj` / `3mf` meshes are fingerprinted in-process (`GeometryFingerprint.compute` → `GeometryWriteback.apply!`) so the same analyze pass can open geometry groups. Pending mesh `archive_members` use the same `GeometryFingerprint.compute` path after streaming **one** zip/7z/rar member (`ArchiveIndexer#extract_member` + `ArchiveMember.normalize_path` jail). Leftover loose meshes enqueue `ComputeGeometryDigestJob`; leftover members enqueue `ComputeArchiveMemberGeometryDigestJob`.

Clustering, highest confidence first:

| reason | confidence | rule |
| --- | --- | --- |
| `content_hash` | `exact` | shared `content_digest` (SHA-256), whole-file Asset only |
| `geometry` | `geometry` | shared `geometry_digest` on `assets` **or** `archive_members` (loose↔member↔member; HITL only) |
| `name_size` | `likely` | leftover same filename + size (Asset only) |

**Rematch.** Terminal groups (`kept` / `dismissed` / `merged`) are never rewritten. If they still match a current cluster (same reason+digest or same name+size, and at least two current members overlap), those members stay reserved and will not open a new group. Only `open` groups are created or have members refreshed. Stale `open` groups that no longer match are destroyed. Re-analyze after a keep/dismiss does not wipe that decision.

**Geometry fingerprint.** `ComputeGeometryDigestJob` / `ComputeArchiveMemberGeometryDigestJob` / `GeometryFingerprint.compute` path-jails the file or parent archive (`LibraryPathJail#resolve_file`), streams a loose STL / OBJ / 3MF or **one** archive member (3MF via zip entry stream — never a whole-archive RAM load), quantizes vertices, drops colors / names / 3MF transforms, and writes `mesh:v1:<sha256>` through `GeometryWriteback.apply!`. The same mesh as a loose file and inside a pack produces the same digest. Gcode, images, and other non-mesh kinds skip. Jail escape, missing member, files over `VIBE_GEO_MAX_BYTES`, or meshes over `VIBE_GEO_MAX_VERTS` / `VIBE_GEO_MAX_SECONDS` skip without crashing and without writing an empty digest. Near-dup grouping stays on `AnalyzeDuplicatesJob`. No native mesh library — pure Ruby + `rubyzip`. 7z/rar members stream through the existing `7z e -so` path (`p7zip-full` in the API image; `VIBE_7Z_BIN` override). Without the CLI, those members skip as unreadable.

External / sidecar write-back (same column) after the curator re-runs analyze:

```
POST /api/v1/geometry/writeback
X-Geometry-Token: $VIBE_GEOMETRY_TOKEN
```

```json
{ "asset_id": 99, "geometry_digest": "mesh:v1:…" }
```

or (XOR — exactly one target):

```json
{ "archive_member_id": 12, "geometry_digest": "mesh:v1:…" }
```

In-process: `GeometryWriteback.apply!(asset_id:, geometry_digest:)` or `GeometryWriteback.apply!(archive_member_id:, geometry_digest:)`. `GeometryFingerprint.compute` returns a `mesh:v1:` digest or `nil` for skip/timeout/empty mesh (loose `Asset` or `ArchiveMember`). The analyze job writes both through `GeometryWriteback` — there is no second writeback API. After switching prefix from `qv1:` to `mesh:v1:`, re-run Analyze so open groups refresh (mixed prefixes will not cluster).

**Archive-member bind.** `ComputeArchiveMemberGeometryDigestJob` path-jails the parent archive, streams one member into a tempfile (the same `ArchiveIndexer#extract_member` path used by previews), hashes with `GeometryMesh`, and `GeometryWriteback.apply!(archive_member_id:, geometry_digest:)`. Never extract the whole archive into RAM or onto disk. NFS stays source of truth; path jail only. Sidecar workers can still `POST /api/v1/geometry/writeback` with `archive_member_id`.

**Frontend bind.** The Duplicates page calls `POST /libraries/:id/duplicates/analyze` (busy + last-run), then `GET /duplicates?library_id=&status=` with Open / Kept / Dismissed / Merged / All. Group `id` is an integer. Prefer `members[]` (`kind: asset | archive_member`). Archive members include `archive_member_id`, parent archive `parent_asset_id` / `parent_filename`, `member_path`, display `archive_path` (`pack.zip → path/foo.stl`), `geometry_digest`, and model card fields. `mergeable` is `false` for `archive_member` and `true` for on-disk assets `ModelComposer` can reparent. `assets[]` remains the loose-file subset (existing cards). Cards show Exact / Geometry / Likely from `confidence`, member count, and 2–4 covers. `/duplicates/:id` is a side-by-side review drawer (cover · title · creator · path · size · content/geometry digest snippets). Owner/contributor Keep / Dismiss / Merge hit `/duplicates/:id/{keep,dismiss,merge}`. If any selected member is archive-resident / `mergeable=false`, merge returns **422** `{ "error": "merge_unsupported" }` — do not offer extract/reparent-out-of-zip. Keep/Dismiss are unchanged. Viewers get a read-only compare.

NFS remains source of truth. The DB is an index. Merge only moves on-disk files through `ModelComposer`'s path jail. Nothing auto-deletes library files.

**Cover write-back** (also `CoverWriteback.apply!` in-process):

```
POST /api/v1/covers/writeback
X-Cover-Token: $VIBE_COVER_TOKEN
```

```json
{
  "model_id": 42,
  "asset_id": 99,
  "status": "ready",
  "cover_url": "/covers/42.webp",
  "cover_placeholder": false,
  "cache_key": "99:1710000000:sha256:…"
}
```

`status` must be `ready` or `failed`. `cover_url` is required when `ready`. Signed-in users can call the same endpoint (useful in tests). `GenerateCoverJob` resolves `jailed_path` with `LibraryPathJail#resolve_jailed`, thumbnails with libvips (`ruby-vips`) within `budget.max_px` / `budget.max_bytes`, and calls `CoverWriteback.apply!`. Cache key is `asset_id + mtime + content_hash`; a model already `ready` for that key is skipped. Mesh/STL/3MF sources use a named preview sibling (`cover`/`preview`/`thumb`/`hero`) under the jail when one exists — there is no 3D renderer in this worker, so a mesh without a preview writes back `failed` (silent status).

Generated files live in `VIBE_COVER_ROOT` (default `api/tmp/covers`) and are served at `GET /covers/:id.webp`. API/worker images need `libvips` (compose Dockerfile installs `libvips42`).

## API (JSON)

All endpoints except `POST /api/v1/session`, invite preview/redeem, and `GET /up` require `Authorization: Bearer <token>`.

- `POST /api/v1/session` `{ email, password }`
- `GET /api/v1/me` (each `user.libraries[]` includes `curation: { last_polled_at, last_provider, last_error }`)
- `GET /api/v1/libraries` · `GET /api/v1/libraries/:id` (every library includes `curation` poll state; owner payload also includes `scan`, `scan_settings`, `cursors`)
- `POST /api/v1/libraries/:id/scan` `{ path_prefix? }` owner-only; `202` + latest scan status
- `GET /api/v1/creators` (`id`, `slug`, `name`, `source`, `model_count`)
- `GET /api/v1/creators/:id` or `GET /api/v1/creators/:slug` (paginated models; `cursor` / `limit` like the catalog)
- `GET /api/v1/models?cursor=&limit=` (cursor pagination; no owner ACL filter; includes `liked`, `like_count`, `bookmark_folder_ids`, nullable `creator: { id, slug, name }`, `cover_status`, `cover_url`, `cover_placeholder`)
- `GET /api/v1/models/:id`
- `POST /api/v1/models/:id/like` · `DELETE /api/v1/models/:id/like`
- `POST /api/v1/models/merge` `{ library_id, source_ids?|asset_ids?, target_id?|title? }` (owner/contributor)
- `POST /api/v1/models/:id/split` `{ merge_id? }`
- `GET /api/v1/likes`
- `GET /api/v1/bookmark_folders` · `POST /api/v1/bookmark_folders` `{ name }`
- `GET /api/v1/bookmark_folders/:id` · `PATCH` · `DELETE`
- `POST /api/v1/bookmark_folders/:id/bookmarks` `{ model_id }` · `DELETE .../bookmarks/:model_id`
- `GET /api/v1/duplicates?library_id=&status=` persisted groups + `members[]` (`kind: asset \| archive_member`, `mergeable`) and `assets[]` (loose files + model cards). `status` is `open` \| `kept` \| `dismissed` \| `merged`; omit for all
- `POST /api/v1/libraries/:id/duplicates/analyze` → `202` + `AnalyzeDuplicatesJob` (owner/contributor)
- `POST /api/v1/duplicates/:id/keep` · `POST .../dismiss` · `POST .../merge` `{ source_ids?|asset_ids?, target_id?, title?, archive_member_ids? }` (owner/contributor; merge calls `ModelComposer` inside the path jail; **422** `{ "error": "merge_unsupported" }` if any selected member is archive-resident)
- `POST /api/v1/geometry/writeback` `{ asset_id \| archive_member_id, geometry_digest }` (`GeometryWriteback.apply!` in-process; `X-Geometry-Token: $VIBE_GEOMETRY_TOKEN` or a signed-in owner/contributor)
- `GET /api/v1/models/:id/archive_members?asset_id=&prefix=&q=&view=tree|flat&limit=&offset=` (nested children by default; `q` searches paths; `view=flat` paginates every member)
- `GET /api/v1/archive_members/:id` (size, path, content type, streamable)
- `GET /api/v1/archive_members/:id/content` (stream one member; `?download=1` for attachment)
- `GET /api/v1/assets/:id/content` (lazy mesh / file stream)
- `GET /api/v1/archive_members/:id/preview` (derived thumb or inline image; mesh returns `use_content`)
- `GET /api/v1/search?q=&tag=&tags[]=&has_preview=&library_id=&uploaded_by_id=&creator_slug=&offset=&limit=` (Meilisearch when configured; Postgres `ILIKE` fallback; facet/filter `creator_slug`)
- `GET /covers/:id.webp` generated cover bytes (libvips webp under `VIBE_COVER_ROOT`)
- `POST /api/v1/covers/writeback` `{ model_id, status: "ready"|"failed", cover_url?, cover_placeholder?, asset_id?, cache_key? }` (`GenerateCoverJob` uses `CoverWriteback.apply!` in-process; `X-Cover-Token: $VIBE_COVER_TOKEN` or Bearer user)
- `GET /api/v1/curator_settings` owner-only — `{ curator_setting: { provider, ollama_url, ollama_model, xai_api_key_status: "set"|"missing" } }`. **Never** returns the raw xAI key. 403 for everyone else.
- `PATCH /api/v1/curator_settings` `{ provider, ollama_url, ollama_model }` owner-only. Does not accept the raw key.
- `PUT /api/v1/curator_settings/xai_api_key` `{ "xai_api_key": "..." }` owner-only. Stores the key encrypted. Response is status only (`set`).
- `DELETE /api/v1/curator_settings/xai_api_key` owner-only. Clears the stored key (`missing`). Compose/CI `XAI_API_KEY` remains the fallback.
- `GET /api/v1/curation_proposals?status=` (`proposals` plus `libraries[]` with `curation` poll state for Frontend bind)
- `POST /api/v1/curation_proposals` `{ library_id, curation_proposal: { kind, summary, payload, sidecar_ref? } }`
- `POST /api/v1/curation_proposals/fetch` `{ library_id }` (owner/contributor; polls sidecar; returns `curation` poll state; 502 includes `curation.last_error`)
- `POST /api/v1/curation_proposals/ingest` webhook (`X-Curator-Token` or user auth)
- `POST /api/v1/curation_proposals/bulk` `{ ids, decision: "approve"|"reject" }`
- `POST /api/v1/curation_proposals/:id/approve` · `POST .../reject`
- `GET /api/v1/printers` · `POST /api/v1/printers` `{ library_id, name, host, protocol_type, enabled?, notes? }` (create/update/delete: owner)
- `PATCH /api/v1/printers/:id` · `DELETE /api/v1/printers/:id`
- `GET /api/v1/print_jobs?status=` · `GET /api/v1/print_jobs/:id` (the signed-in user's jobs only)
- `POST /api/v1/print_jobs` `{ printer_id, model_id, asset_id }` → `202` + `queued` (**library owner** only)
- `POST /api/v1/print_jobs/:id/cancel` (requester only)
- `GET /api/v1/invites` · `POST /api/v1/invites` `{ library_id, email?, role?, expires_in_days? }`
- `GET /api/v1/invites/token/:token` (public preview)
- `POST /api/v1/invites/:token/redeem` `{ email, password, display_name }`
- `POST /api/v1/invites/:id/revoke`
- `POST /api/v1/uploads` `{ library_id, folder_name, relative_path, filename, byte_size }`
- `PATCH /api/v1/uploads/:id` (raw chunk, `Upload-Offset` header, or JSON `chunk_b64`)
- `POST /api/v1/uploads/:id/complete`
- `POST /api/v1/uploads/direct` (multipart convenience for small files / tests)

## Tests

```bash
cd api && RAILS_ENV=test bin/rails db:prepare && bin/rails test
cd ../web && npm run build
cd ../curator && ruby test/run.rb
```

CI runs api, web, and curator jobs on GitHub Actions.

## Layout

```
api/                 Rails 8 API-only application
web/                 React + Vite SPA
curator/             Live curator sidecar (stub / ollama / xai; compose profile `curator`)
fixtures/library/    Sample on-disk collection used by seed/scan
docker-compose.yml   api, worker, db, redis, web, meilisearch (+ optional curator)
```

## Curation sidecar contract

HITL only. Rails never auto-approves and never silently deletes NFS files. `VIBE_CURATOR_URL=stub` stays the CI path (in-process fixtures, no network). The compose sidecar defaults to `VIBE_CURATOR_PROVIDER=stub` and can switch to `ollama` or `xai` without changing the HTTP contract.

3dvibe posts a **locked catalog snapshot** (metadata + path hints only — never blobs or mesh bytes) and upserts whatever comes back as **pending** proposals. The sidecar never deletes NFS files.

`POST {VIBE_CURATOR_URL}/proposals`

```json
{
  "library_id": 1,
  "library_name": "Studio library",
  "library_root": "/library",
  "provider_hint": "ollama",
  "curator_runtime": {
    "provider": "xai",
    "ollama_url": "http://host.docker.internal:11434",
    "ollama_model": "llama3.1",
    "xai_api_key": "<decrypted only on this POST; omitted when provider is stub>"
  },
  "creators_index": [
    { "id": 3, "slug": "mz4250", "name": "Mz4250", "model_count": 12 }
  ],
  "models": [
    {
      "id": 12,
      "folder_name": "signal-horn",
      "title": "Signal Horn",
      "tags": ["stl"],
      "asset_count": 2,
      "byte_size": 1200,
      "creator": { "id": 3, "slug": "mz4250", "name": "Mz4250" },
      "cover_status": "ready",
      "mesh_count": 1,
      "archive_count": 1,
      "has_archives": true,
      "sample_paths": ["signal-horn/horn.stl", "signal-horn/pack.zip"]
    }
  ]
}
```

Existing keys stay stable. New model fields: `creator` (`{ id, slug, name }` or `null`), `cover_status` (`missing` \| `pending` \| `ready` \| `failed`), `mesh_count`, `archive_count`, `has_archives`, `sample_paths` (up to 5 jail-relative asset paths — hints only). New library fields: `creators_index` (budgeted, top 50 by model count), `provider_hint`, and request-scoped `curator_runtime` (POST body only).

Response:

```json
{
  "provider": "ollama",
  "proposals": [
    {
      "sidecar_ref": "stable-id-for-upsert",
      "kind": "tag",
      "summary": "Tag Signal Horn as audio",
      "payload": { "model_id": 12, "folder_name": "signal-horn", "tag": "audio", "tags": ["audio"] }
    }
  ]
}
```

`sidecar_ref` must be **stable** for the same suggestion. Rails upserts pending rows by `(library_id, sidecar_ref)` (unique when present). Reviewed rows are never clobbered. Live providers that rotate refs will create duplicates.

Optional: return `provider` in the body and/or `X-Curator-Provider` so Rails can persist `libraries.last_provider`. When absent, Rails stores the effective provider from `curator_runtime` / owner UI / `VIBE_CURATOR_PROVIDER` / `stub`.

`GET /proposals?library_id=&library_root=&provider_hint=` is a fallback when POST is not implemented. **Do not** put `curator_runtime` or the xAI key on the query string.

Auth: `Authorization: Bearer {VIBE_CURATOR_TOKEN}` and/or `X-Curator-Token`.

### Owner curator settings

Site-scoped singleton `CuratorSetting` (one install). HITL approve/apply is unchanged — no auto-approve, no silent NFS delete. `VIBE_CURATOR_URL=stub` stays the CI path when the owner has not set a UI provider.

**Resolution order** (field by field):

1. Persisted owner UI (`CuratorSetting`) when that field is present
2. Else compose/CI env (`VIBE_CURATOR_PROVIDER`, `VIBE_OLLAMA_URL`, `VIBE_OLLAMA_MODEL`, `XAI_API_KEY` / `VIBE_XAI_API_KEY`)
3. Else `stub` (no secrets)

Rails injects the resolved hash as `curator_runtime` on `POST /proposals` only. If the effective provider is `stub`, `xai_api_key` is omitted. The decrypted key is never written to Meilisearch, never returned on proposal payloads to the SPA, and is filtered from logs (`xai_api_key`, `curator_runtime`).

**Key pattern:** `PATCH` updates provider / Ollama URL / model. `PUT /api/v1/curator_settings/xai_api_key` `{ "xai_api_key": "..." }` sets the key. `DELETE` clears it. Never echo the secret.

**Owner UI:** `/settings/curator` (Avatar menu → **Curator**, or Curation **Configure**). Non-owners do not see the entry point. The key field is a one-shot password input (`autocomplete=new-password`); it is never prefilled from `GET` and is cleared from the DOM after a successful `PUT`. Settings apply on the next **Refresh proposals**. Stub stays available.

**Encryption:** `ActiveRecord::Encryption` on `curator_settings.xai_api_key`. Wire keys with `VIBE_ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`, `VIBE_ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY`, and `VIBE_ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT`, or Rails credentials `active_record_encryption.*`. Compose and CI use documented deterministic test keys. Generate production keys with `bin/rails db:encryption:init`.

**Security:** do not store the xAI key in `localStorage`, cookies, Meilisearch, proposal payloads, or chat paste. The SPA only shows `xai_api_key_status`. Owner-only (403 otherwise).

### Poll observability (Frontend bind)

`FetchCurationProposalsJob` and `POST /curation_proposals/fetch` write three columns on `libraries`:

| Field | Meaning |
| --- | --- |
| `last_polled_at` | Last poll attempt (success or failure) |
| `last_provider` | Sidecar `provider` / `X-Curator-Provider`, else the effective UI/ENV provider used on that poll, else `stub` |
| `last_error` | Last failure message; **cleared on the next success** |

Exposed as `curation: { last_polled_at, last_provider, last_error }` on:

- `GET /api/v1/libraries` and `GET /api/v1/libraries/:id`
- `GET /api/v1/me` → `user.libraries[].curation`
- `GET /api/v1/curation_proposals` → `libraries[].curation`
- `POST /api/v1/curation_proposals/fetch` → top-level `curation` (also on 502)

### Live sidecar (Rendering)

`curator/` implements `GET /health` and `POST|GET /proposals` against the catalog above.

**Request-scoped `curator_runtime` (Rails PR #23).** Rails `CurationSidecar#catalog` injects `CuratorRuntime.for_sidecar` on `POST /proposals` only. The sidecar prefers that hash for the poll and does **not** require a rebuild/redeploy to switch providers. Process ENV is the fallback and is never mutated.

Shape expected from #23 (field by field; blank/null leaves the env value):

```json
{
  "provider": "stub|ollama|xai",
  "ollama_url": "http://host.docker.internal:11434",
  "ollama_model": "llama3.1",
  "xai_api_key": "<decrypted; omitted when effective provider is stub>"
}
```

Sidecar resolution:

1. `curator_runtime.provider` / `ollama_url` / `ollama_model` / `xai_api_key` when present
2. Else sidecar ENV (`VIBE_CURATOR_PROVIDER`, `VIBE_OLLAMA_URL`, `VIBE_OLLAMA_MODEL`, `XAI_API_KEY` / `VIBE_XAI_API_KEY`)
3. Else catalog `provider_hint`, then `stub`

Stub remains the CI default. If runtime says `stub` (or is absent and env/hint resolve to stub), an included `xai_api_key` is ignored — no 503, and the key is stripped from the request-scoped env. `GET /proposals` never reads `curator_runtime` from the query string. The decrypted key is never sent to the LLM prompt, never written into proposal JSON, and is redacted from provider error text.

| Provider | When | Notes |
| --- | --- | --- |
| `stub` | `curator_runtime.provider`, else `VIBE_CURATOR_PROVIDER=stub` (default), or `VIBE_CURATOR_URL=stub` on Rails | Deterministic fixture proposals. CI-safe. No secrets on the wire. |
| `ollama` | `curator_runtime` / UI / `VIBE_CURATOR_PROVIDER=ollama` | Native `POST {VIBE_OLLAMA_URL}/api/chat` or OpenAI `…/v1/chat/completions`. Runtime `ollama_url` / `ollama_model` override env. |
| `xai` | `curator_runtime` / UI / `VIBE_CURATOR_PROVIDER=xai` | `POST {XAI_BASE_URL}/chat/completions` with `curator_runtime.xai_api_key` or `XAI_API_KEY` |

The sidecar ranks models using `creator`, `cover_status`, mesh/archive counts, `sample_paths`, and `creators_index`. Live `sidecar_ref` values are minted from kind + payload so upsert stays stable even if the model rotates ids. Optional `rationale` / `reason` / `explanation` / `confidence` are passed through when the provider returns them and omitted otherwise.

Responses include `provider` and `X-Curator-Provider`. Path-jail drops `../`, hidden segments, nested rename/move destinations, and any delete intent.

Keep apply path-jailed on Rails. Do not auto-approve. Do not delete NFS files from the sidecar.

| `kind` | Payload | Apply |
| --- | --- | --- |
| `tag` | `model_id` / `model_ids` / `folder_name`, `tag` or `tags` | Immediate catalog write |
| `rename` | `model_id` or `folder_name`, `to`, optional `title` | First-level folder rename inside the jail, then scan |
| `move` | same as rename, or `relative_path` + `destination_folder` for one file | Path-jailed move, then scan |
| `merge` | `source_id`/`left_id` + `target_id`/`right_id` (or `from`/`to`) | Move files into `target/source/…`; remove the source dir only if empty |
| `organize` | `shelf` + `model_ids` (tags) or `to` (folder rename) | Tag unless a destination folder is present |

Rename/move destinations must be a single non-hidden segment. `../`, `.hidden`, and `kits/nested` are rejected. Apply never deletes user files.

### Pointing Rails at the live sidecar

1. `docker compose --profile curator up --build` (or run `curator/server.rb` on a Spark/DGX host).
2. Set `VIBE_CURATOR_URL=http://curator:8088` (compose) or `http://<spark-host>:<port>` and a long `VIBE_CURATOR_TOKEN`.
3. Set `VIBE_CURATOR_PROVIDER=ollama` or `xai` on **both** Rails (hint) and the sidecar (adapter), **or** save owner UI settings. `curator_runtime` on POST wins over sidecar env. URL still wins over the hint for "which process to call".
4. Increase `VIBE_CURATOR_TIMEOUT` if inference is slow.
5. Keep HITL approve/apply in Rails. Do not log `curator_runtime`. Do not send the key to the LLM prompt.

Webhook alternative: the curator can `POST /api/v1/curation_proposals/ingest` with the same proposal array and `X-Curator-Token`.

## Printer adapters

`PrinterAdapters` is the only place a printer protocol should live. The SPA has no printer host/port fields on the wire beyond what the owner stored in `Printer`.

```
PrinterAdapters.for(printer) → Mock | Sdcp | YourAdapter
PrinterBridge                 → jail file, call adapter, persist status
DispatchPrintJob              → Sidekiq; rescues and fail_soft! so the UI keeps 2xx
LibraryPathJail#resolve_file  → regular file under the library root only
```

| `protocol_type` | Behavior |
| --- | --- |
| `mock` | Reads the jailed file, simulates sending/printing, marks `succeeded`. No sockets. |
| `sdcp` | Interface only. `submit` raises `NotConfigured`; the job is `failed` with a clear note. |

### Adding a real LAN adapter

1. Implement `PrinterAdapters::Sdcp#submit(absolute_path, job:)` (and optionally `#poll` / `#cancel`) using `printer.host` and `printer.settings`.
2. Keep all I/O inside `Timeout` / `VIBE_PRINT_TIMEOUT`. Never raise out of `PrinterBridge` — call `job.fail_soft!(message)` instead.
3. Leave the Rails controllers and React pages unchanged. Point the printer row at the LAN IP and set `protocol_type=sdcp`.
4. Do not proxy printer APIs through the browser. The worker is the only process that should see the printer.

Resin studio, camera, and consumables are out of scope for this slice.

## License

Use and extend this original 3dvibe codebase in your own studio. No third-party library product is included or required.
