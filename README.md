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
| `owner` | The library admin | Invite/revoke, upload, trigger a full scan, review/apply curation, manage printers |
| `contributor` | Default for invited friends | Browse/search the whole catalog, upload, review/apply curation, and queue prints |
| `viewer` | Optional read-only invite | Browse/search the catalog, see the curation queue, and request a print |

## What you get

- Rails 8 API (Ruby 3.3 in Docker, 3.2+ on the host) with PostgreSQL, Redis, and Sidekiq
- React + Vite + TypeScript gallery with infinite scroll and a dark Tailwind UI
- Owner invite links (optional email, role, expiry) plus a redeem/signup page
- Chunked, resumable uploads (1 MB patches, TUS-style offset) path-jailed to the library root
- Incremental folder scanning with mtime/size/path-prefix cursors; uploads enqueue a targeted rescan
- First-class archive visibility for zip/3mf
- Token auth
- HITL AI curation: sidecar contract, stub curator, ingest, review queue, path-jailed apply
- Postgres `ILIKE` search (Meilisearch is optional via a compose profile)
- In-browser Three.js viewer that **does not** auto-load meshes on cards
- Print-from-browser: owner printer registry, path-jailed Sidekiq dispatch, mock adapter + SDCP interface

## Architecture

```
web (Vite SPA) ──JSON──► api (Rails 8, API-only)
                              │
                              ├── PostgreSQL   catalog, users, invites, uploads, cursors
                              ├── Redis        Sidekiq
                              └── NFS / disk   library root (bind-mounted, read-write)
```

Domain objects (original names):

| Object | Meaning |
| --- | --- |
| `Library` | Root path on disk (your NFS mount) |
| `VibeModel` | One folder under that root |
| `Asset` | An on-disk file, with a content digest when the file is small enough |
| `ArchiveMember` | An indexed entry inside a zip/3mf (7z/rar listing is deferred) |
| `Tag` / `TagAssignment` | Lightweight joins for search and display |
| `User` / `Membership` / `Invite` | Owner, contributor, or viewer |
| `LibraryUpload` | Resumable upload session that lands inside the library jail |
| `CurationProposal` | Sidecar suggestion: pending / approved / rejected |
| `ScanCursor` | Incremental index fingerprint per folder prefix |
| `Printer` | Owner-managed registry entry (name, host/IP, protocol, enabled) |
| `PrintDispatch` | Print job: queued → sending → printing → succeeded/failed/cancelled |

Background jobs:

- `IncrementalScanJob` — walks a library (or one folder prefix after an upload) and updates stale folders
- `DerivePreviewJob` — stub for stills / decimated meshes
- `FetchCurationProposalsJob` — polls the curator sidecar (or in-process stub) and upserts pending `CurationProposal` rows
- `ApplyCurationProposalJob` — applies an approved rename/move/merge (tags apply in-request)
- `DispatchPrintJob` — path-jails a library file and sends it through a printer adapter (mock simulates progress)

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
| Meilisearch (optional) | `docker compose --profile search up` → localhost:7700 |
| Curator stub (optional) | `docker compose --profile curator up` → localhost:8088 |

On first boot the API runs `db:prepare`. Seed the owner and scan the sample library:

```bash
docker compose exec api bin/rails db:seed
# or rescan later
docker compose exec api bin/rails vibe:scan
```

Default owner (override with `VIBE_OWNER_EMAIL` / `VIBE_OWNER_PASSWORD`):

- email: `owner@3dvibe.local`
- password: `vibe-dev-password`

Open the web app, sign in, scroll the gallery, open **Packed Minis**, and expand archive members.

### Print from browser (mock printer)

The browser never talks to a printer. It only calls the 3dvibe API. The API/worker reads the file from the library jail and hands it to an adapter.

```bash
docker compose exec api bin/rails db:seed          # seeds a "Studio mock" printer
# Owner: Printers page → add/edit/remove (or keep the seeded mock)
# Anyone signed in: open Signal Horn → Print → job walks queued → succeeded
# Shared history: Prints
docker compose exec api bin/rails vibe:print       # same path without the UI
```

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

Each first-level directory under the library root becomes a `VibeModel`. Hidden first-level folders (including `.vibe-incoming` used during uploads) are ignored. Files beneath a model folder become `Asset` rows. Zip/3mf files are opened only far enough to read the central directory and, on demand, a single member stream.

## API (JSON)

All endpoints except `POST /api/v1/session`, invite preview/redeem, and `GET /up` require `Authorization: Bearer <token>`.

- `POST /api/v1/session` `{ email, password }`
- `GET /api/v1/me`
- `GET /api/v1/libraries` · `POST /api/v1/libraries/:id/scan`
- `GET /api/v1/models?cursor=&limit=` (cursor pagination; no owner ACL filter)
- `GET /api/v1/models/:id`
- `GET /api/v1/models/:id/archive_members`
- `GET /api/v1/assets/:id/content` (lazy mesh / file stream)
- `GET /api/v1/archive_members/:id/preview`
- `GET /api/v1/search?q=`
- `GET /api/v1/curation_proposals?status=`
- `POST /api/v1/curation_proposals` `{ library_id, curation_proposal: { kind, summary, payload, sidecar_ref? } }`
- `POST /api/v1/curation_proposals/fetch` `{ library_id }` (owner/contributor; polls sidecar)
- `POST /api/v1/curation_proposals/ingest` webhook (`X-Curator-Token` or user auth)
- `POST /api/v1/curation_proposals/bulk` `{ ids, decision: "approve"|"reject" }`
- `POST /api/v1/curation_proposals/:id/approve` · `POST .../reject`
- `GET /api/v1/printers` · `POST /api/v1/printers` `{ library_id, name, host, protocol_type, enabled?, notes? }` (create/update/delete: owner)
- `PATCH /api/v1/printers/:id` · `DELETE /api/v1/printers/:id`
- `GET /api/v1/print_jobs?status=` · `GET /api/v1/print_jobs/:id`
- `POST /api/v1/print_jobs` `{ printer_id, model_id, asset_id }` → `202` + `queued` (worker updates status)
- `POST /api/v1/print_jobs/:id/cancel`
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
docker-compose.yml   api, worker, db, redis, web (+ optional curator, meilisearch)
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
