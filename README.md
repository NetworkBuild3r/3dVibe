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
| `contributor` | Default for invited friends | Browse/search the whole catalog, upload, like/bookmark, review/apply curation, merge/split models |
| `viewer` | Optional read-only invite | Browse/search the catalog, like/bookmark, see the curation queue |

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
- Duplicate review (content hash + filename/size heuristics)

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
| `Asset` | An on-disk file, with a content digest when the file is small enough |
| `ArchiveMember` | An indexed entry inside a zip/3mf (7z/rar listing is best-effort) |
| `Tag` / `TagAssignment` | Lightweight joins for search and display |
| `User` / `Membership` / `Invite` | Owner, contributor, or viewer |
| `LibraryUpload` | Resumable upload session that lands inside the library jail |
| `CurationProposal` | Sidecar suggestion: pending / approved / rejected |
| `ScanCursor` | Incremental NFS fingerprint per folder prefix (mtime, size, inode, nlink, deep-scan time) |
| `ScanRun` | One walk/prune attempt: status, file/folder counts, errors, resume cursor |
| `Printer` | Owner-managed registry entry (name, host/IP, protocol, enabled) |
| `PrintDispatch` | Print job private to the requester: queued → sending → printing → succeeded/failed/cancelled |
| `Like` / `BookmarkFolder` / `Bookmark` | Personal catalog organization (not visibility) |
| `ModelMerge` | Recorded merge so a split can restore first-level folders |

Background jobs:

- `IncrementalScanJob` — incremental NFS walk (or one folder prefix after an upload/curation apply); honors `VIBE_SCAN_*` budgets and re-enqueues when budgeted
- `ScheduledScanJob` — sidekiq-cron entry that queues a scan for every library (default every 6 hours)
- `IndexVibeModelJob` / `RemoveVibeModelIndexJob` / `ReindexSearchJob` — keep Meilisearch in sync after scan, upload, destroy, and curation apply
- `DerivePreviewJob` — copies hot image members out of an archive into a preview cache (mesh rasterization is still a stub)
- `FetchCurationProposalsJob` — polls the curator sidecar (or in-process stub) and upserts pending `CurationProposal` rows
- `ApplyCurationProposalJob` — applies an approved rename/move/merge (tags apply in-request)
- `DispatchPrintJob` — path-jails a library file and sends it through a printer adapter (mock simulates progress)
- `ModelComposer` — merge/split first-level folders and selected files inside the path jail
- `DuplicateFinder` — groups assets by SHA-256 and filename+size (streams hashes; does not slurp archives)

The curation sidecar is `CurationSidecar`. In development/test a blank or `stub` URL generates deterministic fixture proposals. A compose profile runs the same contract as HTTP.

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
| Curator stub (optional) | `docker compose --profile curator up` → localhost:8088 |

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

Search indexes title, folder path, tags, asset filenames/paths, archive-member paths, uploader, `updated_at`, and `has_preview` (mesh or previewable archive member). If Meilisearch is unreachable, `GET /api/v1/search` answers from Postgres and sets `fallback: true`.

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
3. **Duplicates** lists exact hashes and same-name/size groups. Select files and merge if you want one folder.

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
2. Click **Fetch proposals** (or `docker compose exec api bin/rails vibe:curate`).
3. Review before/after, then approve, reject, or use bulk actions.
4. Tags write immediately. Rename/move/merge run through `ApplyCurationProposalJob` inside the library path jail, then enqueue a targeted incremental scan.

```bash
# in-process stub (default in compose: VIBE_CURATOR_URL=stub)
docker compose exec api bin/rails vibe:curate

# HTTP stub curator (same JSON contract a Spark box should implement)
docker compose --profile curator up --build
# set VIBE_CURATOR_URL=http://curator:8088 in .env and restart api/worker
```

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
| `VIBE_CURATOR_URL` | Curator base URL, or `stub` for the in-process fixture generator |
| `VIBE_CURATOR_TOKEN` | Shared bearer token for poll + webhook ingest |
| `VIBE_CURATOR_TIMEOUT` | HTTP timeout in seconds (default 8) |
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

### Archive visibility

`IncrementalScanJob` → `LibraryScanner` → `ArchiveIndexer`. Members are stored with `parent_path` so the API can return a folder page instead of a flat dump.

| Format | Listing | Single-member stream | Notes |
| --- | --- | --- | --- |
| zip / 3mf | **Full** — central directory only | **Full** — 64 KiB copy into a tempfile, then `send_file` | Default path. Parent folders are synthesized when the zip omits directory entries. |
| 7z / rar | **Best-effort** — `7z l -slt` when `7z` is on PATH | **Best-effort** — `7z e -so` of one path | Compose images install `p7zip-full`. Without the CLI, one `(listing pending)` placeholder is stored and the UI says so. |

The indexer never extracts an archive to disk. A huge listing stops at `VIBE_ARCHIVE_MEMBER_LIMIT` and sets `assets.archive_truncated`. A single member larger than `VIBE_ARCHIVE_STREAM_BYTES` is refused.

`DerivePreviewJob` copies up to 24 hot image members (shallow / names like preview, thumb, cover, hero) into `VIBE_PREVIEW_ROOT`. Mesh members stay lazy: the tree shows a Load action; Three.js only runs after a click.

Search (Meilisearch `archive_paths` and Postgres `ILIKE`) includes file member paths, so `hero` still hits Packed Minis. Directory rows and placeholders are excluded from the search document.

## API (JSON)

All endpoints except `POST /api/v1/session`, invite preview/redeem, and `GET /up` require `Authorization: Bearer <token>`.

- `POST /api/v1/session` `{ email, password }`
- `GET /api/v1/me`
- `GET /api/v1/libraries` · `GET /api/v1/libraries/:id` (owner payload includes `scan`, `scan_settings`, `cursors`)
- `POST /api/v1/libraries/:id/scan` `{ path_prefix? }` owner-only; `202` + latest scan status
- `GET /api/v1/models?cursor=&limit=` (cursor pagination; no owner ACL filter; includes `liked`, `like_count`, `bookmark_folder_ids`)
- `GET /api/v1/models/:id`
- `POST /api/v1/models/:id/like` · `DELETE /api/v1/models/:id/like`
- `POST /api/v1/models/merge` `{ library_id, source_ids?|asset_ids?, target_id?|title? }` (owner/contributor)
- `POST /api/v1/models/:id/split` `{ merge_id? }`
- `GET /api/v1/likes`
- `GET /api/v1/bookmark_folders` · `POST /api/v1/bookmark_folders` `{ name }`
- `GET /api/v1/bookmark_folders/:id` · `PATCH` · `DELETE`
- `POST /api/v1/bookmark_folders/:id/bookmarks` `{ model_id }` · `DELETE .../bookmarks/:model_id`
- `GET /api/v1/duplicates?library_id=`
- `GET /api/v1/models/:id/archive_members?asset_id=&prefix=&q=&view=tree|flat&limit=&offset=` (nested children by default; `q` searches paths; `view=flat` paginates every member)
- `GET /api/v1/archive_members/:id` (size, path, content type, streamable)
- `GET /api/v1/archive_members/:id/content` (stream one member; `?download=1` for attachment)
- `GET /api/v1/assets/:id/content` (lazy mesh / file stream)
- `GET /api/v1/archive_members/:id/preview` (derived thumb or inline image; mesh returns `use_content`)
- `GET /api/v1/search?q=&tag=&tags[]=&has_preview=&library_id=&uploaded_by_id=&offset=&limit=` (Meilisearch when configured; Postgres `ILIKE` fallback)
- `GET /api/v1/curation_proposals?status=`
- `POST /api/v1/curation_proposals` `{ library_id, curation_proposal: { kind, summary, payload, sidecar_ref? } }`
- `POST /api/v1/curation_proposals/fetch` `{ library_id }` (owner/contributor; polls sidecar)
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
```

CI runs both jobs on GitHub Actions.

## Layout

```
api/                 Rails 8 API-only application
web/                 React + Vite SPA
curator/             Dev stub curator (compose profile `curator`)
fixtures/library/    Sample on-disk collection used by seed/scan
docker-compose.yml   api, worker, db, redis, web, meilisearch (+ optional curator)
```

## Curation sidecar contract

The sidecar never talks to the GPU from this repo. 3dvibe posts a catalog snapshot and upserts whatever comes back.

`POST {VIBE_CURATOR_URL}/proposals`

```json
{
  "library_id": 1,
  "library_name": "Studio library",
  "library_root": "/library",
  "models": [
    { "id": 12, "folder_name": "signal-horn", "title": "Signal Horn", "tags": ["stl"], "asset_count": 2, "byte_size": 1200 }
  ]
}
```

Response:

```json
{
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

`GET /proposals?library_id=&library_root=` is a fallback when POST is not implemented.

Auth: `Authorization: Bearer {VIBE_CURATOR_TOKEN}` and/or `X-Curator-Token`.

| `kind` | Payload | Apply |
| --- | --- | --- |
| `tag` | `model_id` / `model_ids` / `folder_name`, `tag` or `tags` | Immediate catalog write |
| `rename` | `model_id` or `folder_name`, `to`, optional `title` | First-level folder rename inside the jail, then scan |
| `move` | same as rename, or `relative_path` + `destination_folder` for one file | Path-jailed move, then scan |
| `merge` | `source_id`/`left_id` + `target_id`/`right_id` (or `from`/`to`) | Move files into `target/source/…`; remove the source dir only if empty |
| `organize` | `shelf` + `model_ids` (tags) or `to` (folder rename) | Tag unless a destination folder is present |

Rename/move destinations must be a single non-hidden segment. `../`, `.hidden`, and `kits/nested` are rejected. Apply never deletes user files.

### Pointing at a Spark / DGX curator later

1. Run your real curator (vision model, NudeNet, etc.) so it implements `POST /proposals` above.
2. Set `VIBE_CURATOR_URL=http://<spark-host>:<port>` and a long `VIBE_CURATOR_TOKEN`.
3. Increase `VIBE_CURATOR_TIMEOUT` if inference is slow.
4. Keep this Rails app unchanged — fetch, HITL, and apply stay here.

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
