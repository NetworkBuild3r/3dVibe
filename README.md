# 3dvibe

3dvibe is original software for a solo-operated, NFS-backed 3D model and print library. An owner browses a large on-disk collection; friends can be invited to view (and later print). This repository is a clean-room MVP scaffold — it is not derived from any other 3D library product.

## What you get in this MVP

- Rails 8 API (Ruby 3.3 in Docker, 3.2+ on the host) with PostgreSQL, Redis, and Sidekiq
- React + Vite + TypeScript gallery with infinite scroll and a dark Tailwind UI
- Incremental folder scanning with mtime/size/path-prefix cursors
- First-class archive visibility for zip/3mf (list members; stream one member without loading the archive into RAM)
- Token auth for the owner plus friend invite tokens
- HITL curation proposals (external sidecar interface is stubbed; nothing GPU-side is required)
- Postgres `ILIKE` search (Meilisearch is optional via a compose profile)
- In-browser Three.js viewer that **does not** auto-load meshes on cards
- Print-from-browser API + UI placeholder (no real printer protocol)

## Architecture

```
web (Vite SPA) ──JSON──► api (Rails 8, API-only)
                              │
                              ├── PostgreSQL   catalog, users, proposals, cursors
                              ├── Redis        Sidekiq
                              └── NFS / disk   library root (bind-mounted)
```

Domain objects (original names):

| Object | Meaning |
| --- | --- |
| `Library` | Root path on disk (your NFS mount) |
| `VibeModel` | One folder under that root |
| `Asset` | An on-disk file, with a content digest when the file is small enough |
| `ArchiveMember` | An indexed entry inside a zip/3mf (7z/rar listing is deferred) |
| `Tag` / `TagAssignment` | Lightweight joins for search and display |
| `User` / `Membership` / `Invite` | Owner vs friend access |
| `CurationProposal` | Sidecar suggestion: pending / approved / rejected |
| `ScanCursor` | Incremental index fingerprint per folder prefix |
| `PrintDispatch` | Stubbed print-bridge request |

Background jobs:

- `IncrementalScanJob` — walks a library and updates only stale folders
- `DerivePreviewJob` — stub for stills / decimated meshes
- `ApplyCurationProposalJob` — stub that runs after a human approval

The optional curation sidecar is `CurationSidecar`. It does not need to be running. A future process can POST proposals into `/api/v1/curation_proposals`.

## Quick start (Docker Compose)

```bash
cp .env.example .env
docker compose up --build
```

Or: `bin/dev` (uses Compose when Docker is available).

Services:

| Service | URL |
| --- | --- |
| Web UI | http://localhost:5173 |
| API | http://localhost:3000 |
| API health | http://localhost:3000/up |
| Postgres | localhost:5432 |
| Redis | localhost:6379 |
| Meilisearch (optional) | `docker compose --profile search up` → localhost:7700 |

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
| `VIBE_LIBRARY_HOST_PATH` | Host path bind-mounted into `api` and `worker` |
| `VIBE_LIBRARY_ROOT` | Path **inside** those containers (default `/library`) |
| `VIBE_LIBRARY_NAME` | Display name stored on the `Library` row |
| `VIBE_NFS_SERVER` / `VIBE_NFS_EXPORT` / `VIBE_NFS_MOUNT_OPTIONS` | Host-side mount hints only |

Each first-level directory under the library root becomes a `VibeModel`. Files beneath it become `Asset` rows. Zip/3mf files are opened only far enough to read the central directory and, on demand, a single member stream.

## API (JSON)

All endpoints except `POST /api/v1/session`, invite redeem, and `GET /up` require `Authorization: Bearer <token>`.

- `POST /api/v1/session` `{ email, password }`
- `GET /api/v1/me`
- `GET /api/v1/libraries` · `POST /api/v1/libraries/:id/scan`
- `GET /api/v1/models?cursor=&limit=` (cursor pagination)
- `GET /api/v1/models/:id`
- `GET /api/v1/models/:id/archive_members`
- `GET /api/v1/assets/:id/content` (lazy mesh / file stream)
- `GET /api/v1/archive_members/:id/preview`
- `GET /api/v1/search?q=`
- `GET /api/v1/curation_proposals` · `POST .../approve` · `POST .../reject`
- `POST /api/v1/print_jobs` (always returns `unavailable` in this MVP)
- `POST /api/v1/invites` · `POST /api/v1/invites/:token/redeem`

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
fixtures/library/    Sample on-disk collection used by seed/scan
docker-compose.yml   api, worker, db, redis, web (+ optional meilisearch)
```

## License

Use and extend this original 3dvibe codebase in your own studio. No third-party library product is included or required.
