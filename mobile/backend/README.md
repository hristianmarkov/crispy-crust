# Crispy Crust app backend

The Flutter app uses the explicitly approved existing Supabase project `wpxeuwknbuxbtkkkmcsm` (Multiple ones / Markov). Its database objects are isolated by `public.cc_*` names and the non-exposed `app_private` schema; its media uses the private `kitchen-media` bucket. The existing marketing waitlist objects remain separate and are not read or modified by the app commands. The owner approved sharing the project after the initial plan recommended a separate project. Namespace isolation does not provide separate billing, Auth configuration or failure isolation. No new hosted project was provisioned.

## Run verification

```sh
npm ci
npm run typecheck
npm test
```

Tests execute the real schema and PL/pgSQL commands in PostgreSQL WASM via PGlite, using separate `anon`, `authenticated`, and worker roles. Tests simulate Supabase Auth's `auth.uid()` and storage tables; they do **not** establish deployed gateway/Auth/Storage integration acceptance. HTTP/provider tests use injected adapters. No cloud credentials are needed.

The Supabase CLI is pinned in package-lock.json. It was verified as v3 during implementation. In a restricted environment, set `SUPABASE_HOME` to a writable **task-specific** state directory; do not replace `$HOME`. Discover flags with `npx supabase --help` and the relevant command's `--help`. `supabase init` and `supabase migration new app_kernel` created the local project/migration. The generated migration is the release artifact; `sql/schema.sql`, `sql/features.sql` and `sql/storage.sql` are editable source inputs checked for exact consistency by tests.

## Deployment boundary

The current approved deployment target is `wpxeuwknbuxbtkkkmcsm`. Both app migrations have been applied by the coordinating agent; its verification found the app tables protected by RLS, the waitlist untouched, and no new security-advisor findings. Recheck that evidence when deploying a new version. Do not rename, drop or broaden access to waitlist objects. Supply server secrets through the owner-controlled vault and verify OAuth redirect allowlists/production email sender before changing shared Auth settings. Continue to use local/staging verification for future migrations; do not treat a successful schema deployment as complete Auth/gateway/Storage/provider acceptance.

Function entrypoints are configured in `supabase/config.toml`. `app-api` verifies bearer tokens using Supabase Auth and forwards the original token to PostgREST/RLS; it never uses a service key. The server-only scheduled `job-worker` requires `JOB_WORKER_SECRET`, uses service credentials to lease one durable job, and acknowledges it with the exact lease token. Configure a platform scheduler to POST that worker and monitor retry-exhausted/failed jobs. No successful queueing claim means processing is finished.

## Implemented data/command kernel

- Tenant kitchens and current DB memberships, with strict local/cloud separation.
- Read-only exposed aggregate/event projections; all mutations through checked commands.
- JSON versioned aggregate snapshots with typed identity/tenant/revision/actor/time constraints and append-only actual events. Aggregate kinds map to local Flutter record kinds. The complete specification's many specialised tables are represented by these aggregates **in this kernel**; this is a documented implementation departure, not full completion of every specialised domain schema.
- Atomic per-kitchen push/pull change sequence, CAS conflicts, operation-hash idempotency, immutable tombstones, physical step duplicate detection for explicit `StepCompleted` events.
- Plan acceptance locks shared resources, rejects overlapping reservations, caps slots against equipment capacity (one by default), supersedes future reminders and preserves actual events.
- Hashed single-use expiring invitations, viewer/editor/admin/owner checks, immediate membership revocation.
- Selected-field immutable share snapshots; revocation and blocking. Previously downloaded copies cannot be remotely recalled.
- Separate consent records, daily quota checks, durable leased jobs, stable failures, bounded retries.
- Reports, blocks, reauthentication-gated account-deletion initiation and immediate stale-token write revocation.
- Private media bucket/read policy; no permissive generic client uploads.

Privileged implementations live in non-exposed `app_private`; public RPCs are `SECURITY INVOKER` wrappers. Definers have empty search paths, explicit identity/membership checks, and narrow EXECUTE grants. User metadata never authorises a role. Client writes to billing/staff memberships/provider state are denied.

## API

Base: `/functions/v1/app-api/v1`. Every POST needs `Authorization: Bearer …`, `Idempotency-Key: UUID`, `Content-Type: application/json`. Responses are `{data,request_id}` or `{error:{code,message,retryable},request_id}`. Payload limit 1 MiB; per-object data limit 256 KiB. Native apps omit Origin; configured browser origins are exact allowlist matches.

- `POST /account/bootstrap` `{display_name?}` → `{user_id,kitchen_id}`. Does not upload a library.
- `GET /kitchens`; `POST /kitchens` `{kind:'household'|'production',name}`.
- `POST /sync/push` `{kitchen_id,device_id,operations:[{operation_id,aggregate_id,base_revision,type:'Upsert',kind,data}]}`.
- `GET /sync/pull?kitchen_id=UUID&cursor=0&limit=100` → changes, cursor, has_more and membership revision. `upsert` payload contains `data`; `event` contains typed actual history; `tombstone` forbids resurrection.
- Event mutations use `type:StepStarted|StepCompleted|StepCorrected|ObservationRecorded|FeedRecorded|FeedCorrected|NoteRecorded|PantryConsumed|OutcomeRecorded|HandoffAcknowledged`, `payload`, `occurred_at`, and nonzero base revision. Delete is a `Delete` operation with current revision.
- `POST /bakes/:id/accept-plan` `{kitchen_id,expected_bake_revision,snapshot:{engine_version,tasks:[{step_id,start_at,finish_at}],reservations:[{resource_id,slot,start_at,finish_at}]}}`.
- `POST /kitchens/:id/invite` `{role,expires_in_seconds?}`; `/invites/redeem` `{token}`; `/members/revoke` `{kitchen_id,user_id}`.
- `POST /shares` `{kitchen_id,source_id,expected_source_revision,selected_fields,expires_at?}`; `GET /shares/:token`; `DELETE /shares/:id`.
- `POST /consents` `{purpose,version,granted}`.
- `POST /coach/requests` `{question,consent_version,kitchen_id?,context?:{aggregate_ids,observations}}`; `/imports` `{source:{kind:'url',url}|{kind:'text',text},consent_version}`; `/exports` reserved job contract. `GET /jobs/:id` returns queued/running/complete/failed state, never invented completion.
- `POST /reports` `{target_type,target_id,reason,details?}`; `/blocks` `{user_id}`.
- `POST /account/delete` `{acknowledge_subscription_separation:true}` requires last sign-in within five minutes, initiates job and revokes writes. Transfer shared ownership first.

## Provider implementation and honesty

The coach adapter uses the fixed OpenAI Responses endpoint, an explicitly configured model, `store:false`, a bounded output schema, selected context only, and no schedule mutation authority. Output has observations, possibilities, next check, uncertainty, zero invented reviewed citations and zero automatic plan proposals. Real recipe-grounded retrieval/evaluation is still a launch gate; do not advertise validated coaching from passing mocked adapter tests.

URL import allows only HTTPS, no credentials/ports/fragments, **operator-approved hosts**, public DNS answers, no redirects, bounded MIME/size/time. It extracts Recipe JSON-LD or saves source text as an unvalidated private draft. This intentionally does not fetch arbitrary internet domains. Approved hosts/DNS are trusted operational inputs; public-address checking is not a substitute for a network egress policy. Keep worker outbound network rules restrictive. No import becomes a runnable reviewed recipe automatically.

## Community, staff and account processing

`GET /community/feed` returns only published posts visible under current blocks; `GET /community/mine` includes the caller's pending items. `POST /community/posts {share_id,title}` snapshots an already reviewed selected-field share into a **pending** post. Comments (`GET/POST /community/posts/:id/comments`) also start pending. `POST /community/follows {creator_id,following}` manages opt-in creator follows. Report/block are independent controls. Private journals never become public through feed queries.

Staff endpoints (`GET /staff/pending`, `GET /staff/reports`, `POST /staff/moderate`, `POST /staff/reports/resolve`) require both a private DB staff role provisioned by the operator and a verified `aal2` JWT. Consumer-editable metadata cannot grant staff. Every moderation action has a reason and audit record. Pending public content requires real review; no queue staffing is invented.

`GET /kitchens/:id/members` exposes active member display names/roles only to current members. `POST /members/role` updates permitted roles; only owners may grant admin. `POST /kitchens/transfer` requires a recent Auth sign-in and an active existing target. Personal kitchens cannot be transferred. Revoked inviters' tokens stop redeeming.

The account-deletion worker now performs real provider operations: retrieve authorised private object keys, delete Storage objects in batches, purge owned application data, scrub free-form contributions, retain a pseudonymous/deleted identity for shared numeric history, then delete the Auth user. It cancels queued/running non-deletion jobs immediately on request. Steps are retry-safe and failures are durable; production provider cleanup still needs integration evidence and the disclosed shared-history retention policy. Backups age out under the selected backup policy. This is not a claim that immutable backups or previously downloaded recipients' copies can be erased immediately.

Cloud JSON export uses a service-only job bound to its owner and existing memberships, capped at 500 records/4 MiB; larger/media archives route to the local archive flow rather than pretend completion.

The URL importer is **not an arbitrary-URL-safe fetch service**. The hostname is resolved again by fetch; DNS rebinding is not prevented merely by preflight address checks. Therefore enable it only for operator-owned/trusted approved hosts **and** enforced outbound network rules/proxy that reject private, loopback, link-local and metadata ranges at connection time. Default allowlist is empty. Until that egress policy is verified, leave `IMPORT_JOBS_ENABLED=false`.

Primary adapter references checked during implementation: [Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security), [CLI v3 state directory](https://github.com/supabase/cli/blob/develop/apps/cli/docs/supabase-home.md), [OpenAI Responses create](https://developers.openai.com/api/reference/resources/responses/methods/create). Provider model selection is explicit configuration and must support structured output; no model/price was invented.

## Explicit remaining release blockers

This backend is a tested command kernel, **not the complete launched service**. Hosted status confirmed by the coordinator: four app migrations are applied to the approved shared project; app-api is deployed; worker version 2 is deployed; the dedicated read-only health request returned HTTP 200 with `{ok:true,mode:"heartbeat"}`. The app tables have RLS, waitlist objects were left untouched, and advisors reported only the two pre-existing waitlist informational findings. The processing scheduler is installed but **inactive**. Health did not claim/process any job and does not establish hosted deletion/export acceptance.

Still unverified or incomplete: production positive Auth/email/OAuth and app sign-in flows, complete Supabase gateway/Storage integration tests, edge request-rate policy, active processing/alerts, full snapshot JSON-schema/version-specific validation, cloud onboarding end-to-end evidence, offline-retention cursor reset protocol, privacy/retention approval, staffed moderation and staff UI end-to-end acceptance, actual store/RevenueCat receipt lifecycle tests, signed-Storage/EXIF rejection against real uploads, actual account/Storage/provider deletion acceptance, and large/media server archive streaming. Unconfigured AI/import/image/media/store services fail explicitly. Unsupported cloud-archive variants fail rather than pretend completion. No store purchase, RevenueCat entitlement, AI inference, or hosted user-job processing is claimed verified. The coordinator must obtain the required processing approval before activating cron.

Generic snapshot Upserts preserve their record/revision/change history; they do not automatically mean two different `completion` snapshot IDs represent the same physical step. Use explicit domain-event commands for physical deduplication, and complete the shared-bake reconciliation UI before claiming multi-user action safety. Similarly the plan validator checks chronology/reservations/history; it does not reproduce the full reviewed recipe DAG/biological envelope validator. These requirements remain in the release ledger.

## Verified private media and selected image analysis

`MEDIA_UPLOADS_ENABLED=true` plus server credentials enables `POST /media/uploads` with `{kitchen_id,attachment_target,sha256,mime_type,bytes,width,height}`. All IDs are UUIDs; SHA-256 is lower-case hex. Maximum is 2 MiB, 4096 pixels per axis, 16 megapixels, JPEG/PNG/WebP. The owner must first sync the attachment's aggregate. The command checks current write membership, creates an idempotent pending asset and returns a Storage signed upload URL; the client uploads the bytes with the returned headers and then calls `POST /media/:id/complete {}`.

Completion downloads private bytes under a hard size cap, checks exact length/digest, MIME/container signature, declared dimensions, and rejects JPEG EXIF/IPTC/comments/ICC or PNG/WebP text/EXIF/XMP metadata. Re-encode camera captures locally to remove metadata before upload. Container checks are bounded parsing, **not complete pixel decoding or a food-safety assessment**. Invalid objects are quarantined and removed. Only server-verified uploaded assets pass the private Storage policy. `GET /media/:id/download` produces a 60-second private URL after fresh membership checks. `DELETE /media/:id` removes the object and marks the metadata deleted; existing signed downloads may remain valid until their short expiry. Cancel the local upload task on deletion. Provider upload tokens can outlive a deletion; do not retry a deleted pending asset's old URL. Monitor and clean up orphan/pending objects on the server under the retention policy.

`IMAGE_JOBS_ENABLED=true`, a configured model/API key and a separate `image` consent enable `POST /analysis/requests {consent_version,media_ids:[one or two verified UUIDs],question?,context?:{observations}}`. The worker re-checks consent and current membership at processing, verifies selected private files again, and sends only those bytes and selected observations to the configured model. Results are visible features/possibilities/next check/uncertainty, with `requires_human_review:true`, no confirmed measurements and no automatic plan changes. Neither upload consent nor cloud backup implies image-analysis consent. Worker feature switches are enforced separately from UI routes, so direct queue calls cannot bypass disabled processing.

## RevenueCat server verification and signed webhooks

Configure the RevenueCat project/store products and secret REST API key, and ensure the mobile SDK logs into the current verified Supabase user ID **before** purchasing or restoring. `POST /purchases/verify {}` refreshes that bound subscriber using RevenueCat's server API. An optional `app_user_id` must match the Auth user; raw client receipt/entitlement assertions are not accepted as proof. The configured entitlement-key allowlist and explicit sandbox/production environment determine which subscription states can apply. Unknown environment metadata fails closed. Current implementation supports configured subscription products; non-subscription/lifetime products need a separately verified mapping before being sold.

Deploy `revenuecat-webhook` separately, configure an exact Authorization header and enable provider HMAC signing. Both credentials are required. It verifies `X-RevenueCat-Webhook-Signature` over the **raw** request bytes using HMAC-SHA256 and a five-minute delivery timestamp tolerance, then re-reads the subscriber from the server API. It does not derive paid state from arbitrary webhook/client fields. Event IDs/hashes are persisted idempotently, and older provider snapshots cannot overwrite newer state. Restore/renewal/refund/out-of-order delivery still require actual store sandbox/provider acceptance tests; no payment or purchase has been executed by this task.

Primary references: [RevenueCat webhook HMAC](https://www.revenuecat.com/docs/integrations/webhooks#webhook-signature-verification-hmac), [RevenueCat REST v1](https://www.revenuecat.com/docs/api-v1), [Supabase signed uploads](https://supabase.com/docs/reference/javascript/file-buckets-createsigneduploadurl), [Storage implementation](https://github.com/supabase/storage-js/blob/main/src/packages/StorageFileApi.ts).

## Function deployment file manifests

`app-api` has a thin entrypoint and a tested `runtimeConfig` factory. That factory wires `RestMediaService` when `MEDIA_UPLOADS_ENABLED=true` and the server service key exists; it wires `RevenueCatService` when the RevenueCat server key and service key exist. Disabled/unconfigured adapters return explicit 503 responses. Strict lowercase `true` enables flags; other strings do not. Core Auth/PostgREST requests retain the caller's token. Server adapters never expose private keys to app configuration or responses.

Deploy complete dependency sets with paths preserved:

- **app-api**, entrypoint `app-api/index.ts`: `app-api/index.ts`, `runtime.ts`, `router.ts`, `deletion.ts`, `media.ts`, `billing.ts` (all companion files under `app-api/`).
- **job-worker**, entrypoint `job-worker/index.ts`: that entrypoint, `job-worker/authorize.ts`, `job-worker/handler.ts`, plus `app-api/jobs.ts`, `media.ts`, `router.ts`, `billing.ts`, `deletion.ts`.
- **revenuecat-webhook**, entrypoint `revenuecat-webhook/index.ts`: that entrypoint plus `app-api/billing.ts`, `media.ts`, `router.ts`, `deletion.ts`.

No npm runtime packages are required by these Edge modules. The function config disables gateway JWT verification because app-api verifies tokens through Auth, the worker requires its separate bearer secret, and the RevenueCat endpoint requires both its configured Authorization header and raw-body HMAC. Never deploy an entrypoint without its corresponding verification layer.

The worker supports the Vault-backed, short-lived HMAC dispatch protocol described in `WORKER_DEPLOYMENT.md`; it does not require copying a long-lived bearer into Edge environment settings. `JOB_WORKER_SECRET` remains an optional legacy server-only alternative. The coordinator owns migration review, hosted heartbeat, scheduling activation and secret setup; a function deployment alone does not prove jobs are scheduled. See `HOSTED_MIGRATIONS.md` before using CLI migration commands on the shared project.

The worker dispatcher migration is applied at hosted version `20261111155139`; the cron remains inactive. Automatic approval review rejected forced dispatch because it could process destructive queued jobs. The dedicated `/job-worker/health` path and purpose-scoped helper are applied under migration `20261111155946` and deployed in worker version 2, providing read-only verification without claiming jobs; do not retry the forced dispatcher as a test. See `WORKER_DEPLOYMENT.md` for the exact safe path and the separate processing-approval boundary.
