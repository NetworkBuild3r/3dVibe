# Thin-cut / DRY audit

Investigation only. Grounded in paths in this repo as of `fec750f` (Frontend bind for Curator settings). No production deletes or refactors in this PR.

**North star:** one shared friend library. Invite → see everything. Upload = contribute. NFS/local path is source of truth. Print is an owner-only side door. HITL curator. No private shelves, no federation.

---

## Executive summary

1. **Print is already owner-gated in the API** (`User#can_print?` = owner) but is still a first-class product surface: main rail, model-page panel, two pages, seed mock printer, `vibe:print`, and ~8 `VIBE_SDCP_*` compose knobs.
2. **The data model is multi-library; the product is one pile.** `POST /api/v1/libraries` exists, `library_id` is on almost every payload, and Libraries is titled “Catalogs” — but seed creates one library, the SPA never calls create, and no integration test hits `POST /libraries`.
3. **“Shelves” is leftover language, not leftover visibility.** Bookmarks/likes never hide models. Keep the feature; rename the chrome (`/shelves`, `SaveToShelf`) to match likes/bookmarks.
4. **Curator ceremony is the other fat stack:** two stub proposal generators, five sidecar adapters (Xai/OpenAI nearly copy-paste), six owner key routes, and a 347-line settings page.
5. **`README.md` is 1,030 lines** of env encyclopedia + Frontend/Rendering bind contracts + SDCP wire shapes. That is operator/onboarding tax, not product.
6. **`docker-compose.yml` duplicates ~80 env lines** on `api` and `worker`. Same keys, same defaults.
7. **Serializers are inline and repeated.** `detail_payload` is copied in `vibe_models_controller` and `duplicates_controller`. Cover fields are restated in `VibeModel#as_card`, `DuplicateGroup`, and `DuplicateFinder`.
8. **`IndexVibeModelJob` is off the hot path.** `SearchIndex.enqueue` goes to `BulkIndexVibeModelsJob`. The only `perform` call is a test.
9. **Extract/merge and ops have twin HTTP doors** (`/duplicates/:id/extract*` vs `/archive_members/extract*`; `GET /ops` vs `GET /libraries/:id/ops`). Same services underneath.
10. **Do not cut path jail, HITL, NFS SoT, or shared-library visibility.** Those are already the load-bearing locks. Thin around them.

---

## Cut / demote

Priority = “how much this fights the north star,” not “delete this week.” Risk is what breaks if the cut is sloppy.

### P0 — product shape (demote first, delete later)

| Item | Pointers | Why | Risk if cut badly |
| --- | --- | --- | --- |
| **Print as a rail destination** | `web/src/components/AppRail.tsx` (Prints next to Library/Creators); `web/src/App.tsx` `/prints`; `web/src/pages/PrintsPage.tsx` | Print is owner-only. Every friend sees a Prints nav item. | Hide from rail / move under Avatar. Keep `/prints` for the owner who queued a job. |
| **Print panel on every model** | `web/src/pages/ModelPage.tsx` (~lines 64–159, 395–478): always fetches `api.printers()`, always renders a Print heading + `OWNER_ONLY_COPY` for non-owners | Viewers/contributors pay a printers round-trip and a print block on the shared catalog page | Collapse behind owner + `?print=1` or a details disclosure. Do not delete enqueue. |
| **Libraries as “Catalogs”** | `web/src/pages/LibrariesPage.tsx` heading “Catalogs”, multi-select list; Avatar → Libraries; `can_manage_libraries` | One shared pile. This page is a useful **scan console**, not a multi-library product | Rename / fold into owner settings. Keep Scan now + cursors. |
| **`POST /api/v1/libraries` create** | `api/app/controllers/api/v1/libraries_controller.rb` `#create`; `api/config/routes.rb` `resources :libraries, only: %i[index show create]` | No SPA caller (`api.createLibrary` does not exist). No `post "/api/v1/libraries"` test. Seed/`VIBE_LIBRARY_ROOT` is how a library is born | Lock or 410. Do not drop `Library` / membership — that is the invite lock. |
| **README print + SDCP as onboarding** | `README.md` “Print from browser”, “Printer adapters”, SDCP JSON (~lines 139–149, 954–1026) | Makes print look like a pillar. Product is the catalog | Move to `docs/print-adapters.md` later. Keep a one-liner: owner side door, mock in CI. |

### P1 — unused / parallel doors (safe after a lock test)

| Item | Pointers | Why | Risk |
| --- | --- | --- | --- |
| **`IndexVibeModelJob`** | `api/app/jobs/index_vibe_model_job.rb`; only `perform_now` in `api/test/jobs/jobs_test.rb`. Hot path: `SearchIndex.enqueue` → `SearchIndexBuffer` → `BulkIndexVibeModelsJob` | Dead production enqueue. README still lists it as a peer of bulk index | Low if tests switch to `SearchIndex#upsert`. Keep `RemoveVibeModelIndexJob`. |
| **Legacy curator key aliases** | `web/src/api.ts` `setCuratorXaiApiKey` / `clearCuratorXaiApiKey` (generic `setCuratorApiKey` already exists); `web/src/curatorSettings.ts` deprecated `XaiApiKeyStatus` | First-provider leftover after OpenAI/Anthropic | Low. SPA already uses the generic pair. |
| **`hasTestPrintApi`** | `web/src/prints.ts`; asserted false in `web/src/prints.test.ts` | Guards a `testPrint` client method that is not on `api` | None. Delete helper + test. |
| **`vibe:print` rake** | `api/lib/tasks/vibe.rake` task `:print` | Operator ceremony for a demoted feature | Low. CI uses HTTP + job tests. |
| **Seeded Studio mock printer + print copy in seed output** | `api/db/seeds.rb` `printers.find_or_create_by!(name: "Studio mock")` | Fine for CI; loud for a friend-library install | Keep create-if-empty for tests; stop advertising in README/quick start. |
| **Printers page library picker** | `web/src/pages/PrintersPage.tsx` `libraryId` + `api.libraries()` | One library | Low. Default `user.libraries[0]`. |
| **Invite / upload `library_id` required in SPA** | `web/src/pages/InvitesPage.tsx`; `web/src/pages/UploadPage.tsx`; `api.createInvite` / `createUpload` | Same | Medium if you ever truly add a second mount. Product says you will not. |
| **Organize “shelf” payload language** | `api/app/services/curation_stub_proposals.rb` `move` → `*-shelf`, `organize` `shelf: "fixture"`; `curator/stub_proposals.rb` same; `CurationApplier` / `CurationPreview` read `payload["shelf"]` as a **tag** | Sounds like Manyfold private shelves. Apply is tags, not a shelf table | Low if you rename the key to `tag` and keep the organize kind. |
| **Moonraker / OctoPrint comments** | `api/app/services/printer_adapters.rb` header | Speculative adapters. Not implemented | None. |

### P2 — docs / env / chrome fat (cut after P0)

| Item | Pointers | Why | Risk |
| --- | --- | --- | --- |
| **SDCP env sprawl on default compose** | `docker-compose.yml` `VIBE_SDCP_*` ×8 on both `api` and `worker`; `.env.example`; `README.md` env table | Print-demoted knobs in every `docker compose up` | Low if adapter keeps `ENV.fetch` defaults in `printer_adapters/sdcp.rb`. |
| **Prints page 800 ms poll** | `web/src/pages/PrintsPage.tsx` | Ceremony for a side door | Low. Slow to 3s or poll only while `ACTIVE_JOB`. |
| **`README.md` API + gallery bind + curator vision encyclopedia** | `README.md` ~561–739, 678–952 | Bind notes belong next to the code or in short `docs/` slices | Medium only if you delete the only copy of the sidecar contract — **split**, do not trash. |
| **`fixtures/generate_library.rb`** | `fixtures/generate_library.rb` | Extra sample folders; committed `fixtures/library/` already exists | Low. Keep if someone regenerates fixtures; do not put it on the happy path. |
| **Dual upload convenience** | `POST /uploads/direct` in `uploads_controller.rb`; README “multipart convenience for small files / tests” | Second write path into the same jail | Keep for tests. Do not teach it in the product README. |
| **`can_*` permission aliases** | `api/app/models/user.rb`: `can_curate?` = `can_upload?`; `can_merge?` = `can_curate?`; `can_print?` = `owner_of?` | Extra flags on `/me` and every library serialize | Low to collapse **new** flags; do not change meaning of owner vs contributor. |

**Not recommended as a mass delete:** SDCP adapter (`api/app/services/printer_adapters/sdcp.rb` + transports). It is the only non-mock print path and is already owner-jailed. Demote it from chrome/docs; keep the code.

**Not dead:** Meili + Postgres fallback (`api/app/services/model_search.rb`, `meilisearch_client.rb`). That is resilience, not duplication of product features.

---

## Simplify

Same priority idea: less code, same shared library.

| P | Item | Pointers | Do this | Risk |
| --- | --- | --- | --- | --- |
| P0 | **One implicit library** | `LibraryInfo.library_id` on cards, search, invites, uploads, printers, duplicates, ops; `ScanButton` lists libraries then picks `can_scan` | Resolve “the library” from `GET /me` → `user.libraries[0]` (or `Library.first` server-side). Stop asking the client to choose | Medium if a test install has two `Library` rows — add a uniqueness guard or “ignore extras” policy first |
| P0 | **Owner settings as one place** | Avatar: Libraries, Invites, Curation, Curator, Printers | One `/settings` with Scan / Invites / Curator / Print (collapsed). Curation queue stays a contributor tool at `/curation` | Low if routes remain as redirects |
| P1 | **Curator key routes → one pair** | `api/config/routes.rb` six `put`/`delete` key actions; `CuratorSettingsController#update_xai_api_key` … `#destroy_anthropic_api_key` already share `update_secret!` / `destroy_secret!` | `PUT/DELETE /curator_settings/:provider/api_key` | Low. Tests in `api/test/integration/curator_settings_test.rb` |
| P1 | **Extract lives in one controller** | `DuplicatesController#extract` / `#extract_and_merge` and `ArchiveMembersController#extract` / `#extract_and_merge` both call `ArchiveMemberExtractor` | Keep `/archive_members/extract*` as the primitive; duplicates endpoints become thin wrappers that attach `group` / `review` | Medium — Frontend `api.extractDuplicate` vs `extractArchiveMembers` (`web/src/api.ts`, `web/src/duplicates.ts`, `DuplicateReview.tsx`) |
| P1 | **Ops snapshot one GET** | `LibrariesController#ops` and `OpsController#show` both `OpsSnapshot.new(library).as_api` | Keep `GET /ops` (optional `library_id`). Make library member a redirect or drop | Low. `OpsStrip` already uses `api.ops()` + `api.libraryScan` |
| P1 | **Table-drive curator providers** | `curator/providers.rb` `Xai` / `Openai` (~45 lines each, same `ChatClient` + temperature); `Anthropic` is the real variant | One `OpenAICompat` class (base URL, key, model, not-configured error). Keep Anthropic + Ollama native | Low if contract tests stay (`curator/test/providers_test.rb`) |
| P1 | **Curator settings page** | `web/src/pages/CuratorSettingsPage.tsx` (347 lines) | Render key fields from `CURATOR_KEY_PROVIDERS` / `PROVIDER_OPTIONS` already in `curatorSettings.ts` | Low |
| P2 | **Compose env** | `docker-compose.yml` `api.environment` ≈ `worker.environment` | YAML anchor (`x-vibe-env`) plus the few api-only keys (`WEB_ORIGIN`, `SECRET` already shared) | Low. Diff the two blocks before anchoring — they are not 100% identical (api has `WEB_ORIGIN`, owner email/password) |
| P2 | **Mesh decode files** | `web/src/meshDecode.ts` (264), `meshDecodeClient.ts` (132), `meshDecodeProtocol.ts` (35), `meshDecode.worker.ts` (41), `meshViewer.ts` (151), `MeshViewer.tsx` (251) | Do **not** collapse worker + protocol. Optional: merge `meshDecodeClient` into `meshViewer` if the extra hop buys nothing | Medium — abort + budget behavior is load-bearing |
| P2 | **`/models` vs `/search`** | `web/src/gallery.ts` `usesSearchEndpoint` (text `q` → search; chips → `/models`); `ModelCatalogFilters` already shared | Keep the split. Do not invent a third catalog API. Document in one table (README already has it) | High if you merge pagination styles (`cursor` vs `offset`) |
| P2 | **User permission methods** | `user.rb` `#api_payload` | Stop adding new `can_*` without a role change. Frontend already keys off `can_invite` / `can_upload` / `can_print` | Low |

---

## DRY

Proposed shared modules and the call sites to merge. Prefer extract-on-next-touch, not a big-bang “shared” gem.

### Backend

| Shared module | Merge these | Notes |
| --- | --- | --- |
| **`VibeModel.detail_payload(model, viewer:)`** (next to existing `card_payloads` / `as_card` in `api/app/models/vibe_model.rb`) | `API::V1::VibeModelsController#detail_payload`; `API::V1::DuplicatesController#detail_payload` (byte-identical asset hash) | First, cheapest DRY. |
| **`DuplicateMemberPresenter`** (or methods on `DuplicateGroup`) | `DuplicateGroup#serialize_loose_member` / `#serialize_archive_member` / `#serialize_asset`; `DuplicateFinder#serialize_asset` / `#serialize_archive_member` | Finder is analyze-time (no `cover_*`); group is API. Share the identity fields; add covers only in `as_api`. |
| **`ServiceToken.authorized?(request, env_key:, header:)`** | `ApplicationController#cover_authorized?` / `#curator_authorized?` / `#geometry_authorized?` (same Bearer + `X-*-Token` + `secure_compare`) | Three copies, three env vars. Do not merge the **tokens** — only the check. |
| **`JobBudget` (clock, `exhausted?`, `reason`)** | `ScanBudget`, `DuplicateBudget`; `GeometryBudget` is a cousin (verts/bytes) | Shared monotonic clock + “0 = unlimited”. Keep domain caps. |
| **`CurationStub` one implementation** | `api/app/services/curation_stub_proposals.rb` (~107 lines); `curator/stub_proposals.rb` (~119 lines) | Same refs (`stub:tag:…`, `*-curated`, `*-shelf`, `stub:organize:fixture`). Rails in-process stub is the CI default (`VIBE_CURATOR_URL=stub`). Sidecar stub is profile `curator`. Extract a tiny shared file **or** make Rails HTTP to sidecar in all non-test envs and keep one stub. |
| **`ArchiveMemberExtractor` response helper** | `DuplicatesController#extract_payload`; `ArchiveMembersController` extract JSON | Same `{ model, assets, extracted, merge }`. |
| **`Writeback` token + stringify** | `CoverWriteback` / `GeometryWriteback` constructors | Small. Optional. |
| **Test: `create_library!(owner:, contributor:, viewer:)`** | Every `api/test/integration/*` repeats `Library.create!` + three `Membership.create!` | `api/test/test_helper.rb` already has `create_owner!`, `create_user!`, `auth_header`, mesh writers. Add the pile helper; do not rewrite all tests in one PR. |

### Frontend

| Shared module | Merge these | Notes |
| --- | --- | --- |
| **`web/src/types.ts` (or `api/types.ts`)** | Types currently living in `web/src/api.ts` (1,077 lines: ~520 types + client) | Domain modules (`prints.ts`, `gallery.ts`, `covers.ts`, `curatorSettings.ts`, `duplicates.ts`, `ops.ts`, `archives.ts`, `creators.ts`) already exist and re-import types from `api.ts`. Split types first; keep `api` as the `request()` + methods object. |
| **`useLibrary()`** | `ScanButton`, `LibrariesPage`, `PrintersPage`, `InvitesPage`, `UploadPage`, `OpsStrip`, `DuplicatesPage` each fetch `/libraries` and pick `[0]` | One hook: `{ library, scan, canScan }`. |
| **Creator chrome** | `CreatorHeader.tsx`, `CreatorListItem.tsx`, `CreatorPackCard.tsx` | All: `CoverMosaic` + `modelCountOf` + `modelCountLabel`. Keep three layouts; extract `<CreatorIdentity covers size />`. |
| **Status tone** | `LibrariesPage` `statusTone` / `formatWhen`; `prints.ts` `jobStatusClass`; curation/duplicates chips | Optional `format.ts` already has `formatBytes` / `formatRelativeTime`. Add `formatWhen` + scan/job tone maps there. |
| **Drop unused print API aliases** | `setCuratorXaiApiKey`; `hasTestPrintApi` | See P1 cuts. |

### Curator / compose

| Shared module | Merge these | Notes |
| --- | --- | --- |
| **`OpenAICompat` provider** | `VibeCurator::Providers::Xai`, `Openai` | See Simplify. |
| **Compose `x-vibe-env`** | `docker-compose.yml` `api` + `worker` `environment:` | See Simplify. |
| **Env alias table (document, then stop adding)** | `XAI_API_KEY` / `VIBE_XAI_API_KEY` (and OpenAI/Anthropic/base URL twins) in `CuratorRuntime::SECRET_ENV` and `curator/config.rb` | One canonical name per secret. Keep the alias one release if `.env` files exist. |

### Scan / index (do not invent a third path)

These look duplicate and are **not**:

| Path | Role |
| --- | --- |
| `LibraryScanner` + `IncrementalScanJob` / `ScheduledScanJob` / `vibe:scan` | NFS walk. One scanner. Keep. |
| `SearchIndex` + buffer + `BulkIndexVibeModelsJob` | Meili write. Keep. |
| `GET /models` + `ModelCatalogFilters` | Postgres gallery (chips, cursor). Keep. |
| `GET /search` + `ModelSearch` | Text query; Meili then ILIKE. Keep. |
| `CoverWriteback` / `GeometryWriteback` | Rendering hooks. Parallel by design. DRY only the token helper. |
| `ComputeGeometryDigestJob` / `ComputeArchiveMemberGeometryDigestJob` | Thin wrappers around `GeometryFingerprint` + writeback. Fine as two jobs (different ids / skip rules). |

---

## Do not cut

These are the shared-library locks. Thin *around* them.

| Lock | Where | Why |
| --- | --- | --- |
| **Path jail (Rails)** | `api/app/services/library_path_jail.rb`; used by scanner, uploads, composer, extractor, curation apply, print resolver, covers, geometry, duplicate hash | NFS writes must not escape the mount. Covered by `api/test/services/library_path_jail_test.rb` and many integration jail tests. |
| **Path jail (sidecar)** | `curator/path_jail.rb`; `curator/proposal_batch.rb` | Sidecar must not suggest `../` or deletes. **Do not “share one class” across processes** unless it is a copied file with tests on both sides. Two jails are cheaper than one clever import. |
| **HITL curator** | `CurationSidecar`, `CurationApplier`, `ApplyCurationProposalJob`, approve/reject/bulk; SPA `CurationPage` | Rails never auto-approves. Stub/live only upsert **pending**. |
| **NFS / disk as source of truth** | `Library#root_path`, `LibraryScanner`, `VIBE_SCAN_ALLOW_EMPTY_PRUNE` default 0, no inotify | Catalog rows are an index. Empty root must not wipe the pile. |
| **Shared visibility** | `ApplicationController#accessible_libraries` → `Library.all`; `#accessible_models` → `VibeModel.all`; comments in `application_controller.rb` and `creator_hint.rb` | Roles gate **writes** (invite / upload / print / merge), not who sees a card. |
| **Invite → membership** | `Invite`, `Membership` roles `owner` / `contributor` / `viewer` | Friends see everything after redeem. Do not add per-user hidden folders. |
| **Likes / bookmark folders as personal org** | `Like`, `BookmarkFolder`, `Bookmark`; `web/src/pages/BookmarksPage.tsx` | Pillar. They must stay non-ACL. Rename “Shelves”; do not remove. |
| **Dedup HITL** | `AnalyzeDuplicatesJob` (on-demand, not every scan); keep/dismiss/merge; archive `merge_unsupported` until extract | Near-dups are never auto-deleted from NFS. |
| **Meili fallback** | `ModelSearch` + `VIBE_SEARCH_FALLBACK_*` | Catalog must work when Meili is down. |
| **Cover / geometry service tokens** | `VIBE_COVER_TOKEN`, `VIBE_GEOMETRY_TOKEN` | Writeback is a Rendering hook, not a public edit. |
| **Scan queue isolation** | `ScanSettings::CRITICAL_QUEUES`; Sidekiq scan capsule | Overnight walk must not starve API/print/covers. |
| **Upload jail + chunked write** | `UploadsController` + `LibraryPathJail` + `.vibe-incoming` | Contribute path for the shared pile. |

---

## Suggested PR sequence

Small slices. Each slice should leave CI green (`api` / `web` / `curator` jobs in `.github/workflows/ci.yml`). Do not combine a print demote with a curator rewrite.

### 1. Frontend — print off the home screen

- Remove Prints from `AppRail`.
- Keep `/prints` + Avatar “Printers” for owners.
- Hide the Model page Print block unless `user.can_print` (no `OWNER_ONLY_COPY` slab for friends).
- Optional: stop `api.printers()` unless owner.
- Files: `AppRail.tsx`, `ModelPage.tsx`, `AvatarMenu.tsx`.
- Tests: `web/src/prints.test.ts` (behavior helpers stay).

### 2. Frontend — shelves → bookmarks (copy only)

- Rail label + `/shelves` redirect to `/bookmarks` (or keep URL, change label).
- `SaveToShelf` → “Save to bookmarks”.
- Files: `App.tsx`, `AppRail.tsx`, `SaveToShelf.tsx`, `BookmarksPage.tsx`.
- Do **not** drop `bookmark_folders` API.

### 3. Frontend — one library in the chrome

- `useLibrary()`; Scan button / invites / upload / printers stop listing “catalogs”.
- Libraries page → “Library scan” (single root, no Catalogs list UI unless `libraries.length > 1` — and treat that as a warning).
- Files: new hook, `ScanButton.tsx`, `LibrariesPage.tsx`, `InvitesPage.tsx`, `UploadPage.tsx`, `PrintersPage.tsx`.

### 4. Backend — lock multi-library create

- Integration test: `POST /api/v1/libraries` is forbidden or gone.
- Then remove `#create` (or `410`).
- Keep `index` / `show` / `scan` / `ops`.
- Files: `libraries_controller.rb`, `routes.rb`, new test next to `libraries_scan_test.rb`.

### 5. Backend — `detail_payload` + test pile helper

- Move detail JSON onto `VibeModel`.
- Add `create_shared_library!` to `api/test/test_helper.rb`; adopt in the next test you touch, not all 14 integration files at once.

### 6. Backend — extract/ops doors

- One extract primitive; duplicate routes delegate.
- One ops GET.
- Frontend `api.ts` can keep both method names as aliases for one release.

### 7. Curator — one stub + OpenAI-compat

- Single stub proposal list (Rails CI path remains `VIBE_CURATOR_URL=stub`).
- Collapse Xai/OpenAI provider classes.
- Collapse key routes.
- Files: `curation_stub_proposals.rb`, `curator/stub_proposals.rb`, `curator/providers.rb`, `curator_settings_controller.rb`, `CuratorSettingsPage.tsx`.
- **HITL apply path unchanged.**

### 8. Rendering — tokens only

- Shared `ServiceToken` check for cover / geometry / curator ingest.
- Do not merge writeback payloads.
- Do not delete `Compute*GeometryDigestJob`.

### 9. Design / docs

- Split `README.md`: product + quick start stay; move API catalog, sidecar contract, SDCP wire, env encyclopedia to `docs/api.md`, `docs/curator.md`, `docs/print.md`, `docs/env.md` (follow-up PRs).
- Compose: `x-vibe-env` anchor; SDCP vars only when print profile is on (optional).
- Drop print from the default “What you get” list; one sentence under owner tools.

### 10. Optional delete (only with a red-then-green test)

- `IndexVibeModelJob` + README mention, after asserting `SearchIndex.enqueue` never enqueues it (already true in `search_index_test.rb` / `model_search_test.rb`).
- `hasTestPrintApi`.
- `setCuratorXaiApiKey` aliases once settings tests only use the generic pair.

---

## Inventory (for the next slice)

### Rails surfaces that look “Manyfold-shaped” but are in use

| Surface | Role vs north star |
| --- | --- |
| `Library` + `Membership` | Needed for invite/roles. **Not** federation. |
| `BookmarkFolder` | Personal org. Rename UI. |
| `Printer` / `PrintDispatch` | Owner side door. Demote chrome. |
| `CurationProposal` kind `organize` + `shelf` | Tag apply. Rename payload. |
| `libraries.create` | Unused door. Lock. |

### SPA routes today (`web/src/App.tsx`)

| Route | Keep / demote |
| --- | --- |
| `/` gallery, `/models/:id` | Keep (model print block: demote) |
| `/creators`, `/creators/:slug` | Keep |
| `/shelves` | Keep feature; rename |
| `/duplicates`, `/duplicates/:id` | Keep |
| `/curation`, `/settings/curator` | Keep |
| `/upload` | Keep |
| `/invites`, `/invite/:token` | Keep |
| `/prints`, `/printers` | Demote (owner tools) |
| `/libraries` | Demote to scan/settings |

### What this audit did not do

- No production refactors.
- Did not treat `IndexVibeModelJob` as proven-dead enough to delete here (tests still call `perform_now`).
- Did not run a runtime unused-export sweep beyond grep (e.g. every `web/src` export).
- Did not claim federation code exists — **none found** (no ActivityPub, no remote follows). The leftover is **multi-library + shelves naming**, not a federated protocol.

---

## How to use this doc

Pick one numbered slice. Cite the files in that slice’s PR. If a cut is not in this list, it is speculative — go back to the north star before deleting.
