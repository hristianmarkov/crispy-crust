# Worker deployment and read-only health verification

The coordinator applied the Vault/dispatcher migration as `20261111155139_crispy_mobile_worker_vault_dispatch_v1` and deployed worker version 1. The named processing cron job remains **inactive**. The coordinator subsequently applied read-only health migration `20261111155946_crispy_mobile_worker_readonly_health_v1` and deployed worker version 2. The coordinator verified the dedicated health request: pg_net request ID 1 returned HTTP 200 with `{ok:true,mode:"heartbeat"}` and no timeout. This verifies transport/health authorisation only, not hosted user-job processing.

## Approval boundary

Automatic approval review rejected invoking the forced dispatcher because it could claim/process destructive queued jobs; empty job/profile checks did not remove the race in which a job could appear concurrently. **Do not retry the forced dispatcher or use it as a heartbeat workaround.** The safer alternative requested by review is a dedicated health endpoint that never enters job processing.

Activation of the processing cron is a separate operation and must remain inactive until the owner/coordinator has the required explicit approval. Successful health verification does not authorise processing account-deletion or other queued jobs.

## Secret and capability protocol

A random long-lived 256-bit HMAC key is generated inside PostgreSQL and encrypted in Vault under `crispy_crust_worker_hmac_v1`. Its value is never returned by migrations, stored in source/cron commands, or sent as an HTTP bearer. `pg_net` temporarily stores outgoing headers, so HTTP uses only short-lived, single-use capabilities. Trusted database administrators can still access Vault; Vault is not protection from the database owner.

Processing capabilities use the existing `v1.<timestamp>.<nonce>.<HMAC>` protocol and the service-role-only `cc_worker_authorize` RPC. They remain reserved for separately approved processing.

Read-only verification has a **different signed purpose**: `v2.heartbeat.<timestamp>.<nonce>.<HMAC>`. The signature includes the heartbeat purpose and the database nonce row has `purpose='heartbeat'`. `cc_worker_authorize_health` checks selected database role and verified JWT role are both `service_role`, checks HMAC/two-minute expiry, and consumes the nonce once. It returns a boolean only. Ordinary clients cannot execute either authorizer, read nonce rows or invoke signature/dispatch helpers.

A heartbeat capability cannot authorise the processing route, even if the optional legacy worker secret is accidentally set to that exact capability. Changing its URL, body or query mode does not change its signed scope. Stripping the purpose and reusing the signature also fails HMAC verification.

## Read-only health design

`POST /functions/v1/job-worker/health` authenticates using only the dedicated heartbeat capability, then immediately returns:

```json
{"ok":true,"mode":"heartbeat"}
```

That branch never calls `processJobs`, `runJobs`, `cc_worker_claim`, deletion, export, AI or another provider. No body/query mode is read. Unknown paths return 404. Authentication consumes only its administrative one-time nonce; no user job/data is read or changed.

`app_private.cc_worker_heartbeat()` is a separate owner-only SQL helper with **no arguments**. It creates a heartbeat capability and sends it to the literal approved project's `/job-worker/health` URL. It cannot choose another path or delegate to the forced dispatcher. It never reads `cc_jobs`. Tokens/key material are not returned; the only return value is a pg_net request ID.

## Coordinator application and verification

1. Review `sql/worker_health.sql` and the applied read-only health migration. It adds purpose-scoped health authorisation and the private heartbeat helper. It does not activate/change any cron job or execute an HTTP request during application.
2. That migration is already applied as `20261111155946`; its local filename/history record are aligned. Do not reapply it or repair hosted history.
3. Worker version 2 was deployed with these preserved relative paths: `job-worker/index.ts`, `job-worker/authorize.ts`, **`job-worker/handler.ts`**, and `app-api/jobs.ts`, `media.ts`, `router.ts`, `billing.ts`, `deletion.ts`. The handler module is necessary: it enforces the early return before job-processing code.
4. Keep AI/image/import flags off until their provider/privacy/egress configurations are ready. Keep the processing cron inactive throughout health verification.
5. Request the review-approved read-only heartbeat:

   ```sql
   select app_private.cc_worker_heartbeat() as request_id;
   ```

   Inspect only the corresponding `net._http_response` status/content. Never select/log outgoing headers or Vault values. Expected HTTP result: 200 and exactly the heartbeat object above, regardless of queued jobs. Check administrative nonce-use booleans/counts and unchanged job status/count metadata as appropriate; never invoke a job-claim function to verify health.
6. Record hosted service-role/JWT-role behaviour and endpoint response. Local stubs alone cannot establish hosted gateway transport; the coordinator subsequently observed the successful read-only health response described above. Do not activate processing as part of this check.

## Processing activation remains separate

The existing named job is `crispy-crust-mobile-job-worker-v1`. Do not activate it until explicit processing approval is available. If approval review still blocks that operation, report the block and obtain the required owner decision; do not substitute another scheduler, invocation path or query to bypass it.

After approval, the coordinator can review the named job's activation and real fixture-processing acceptance separately. No other jobs should be altered. Its default worker processes export/deletion only; enabling AI/image/import remains explicit server configuration. Each invocation claims one job; actual queue throughput requires measurement.

## Operations

Disable only the named processing job when needed; preserve unrelated marketing jobs. Disable/review schedules on restored or cloned databases before changing endpoints. Current helpers target the explicitly approved project. Nonce records are bound to the database, so a cloned database's fresh nonce is absent in production, but restored schedules should still be disabled/reviewed.

Rotate signing material entirely within SQL using `vault.update_secret`, never returning it. Rotation invalidates outstanding capabilities. Keep capabilities out of logs/errors/metrics and diagnose using request IDs, boolean nonce status and safe job metadata.

## Verification performed locally

TypeScript checks and the backend suite use real PostgreSQL/pgcrypto for signatures, strict role checks, expiry, tamper and replay prevention. Tests include a queued destructive-job fixture that remains untouched by health, and handler spies proving claim/deletion processing cannot run on health even when body/query/path flips are attempted. Vault encryption and pg_cron/pg_net transport are represented by isolated provider stubs; hosted transport remains the coordinator's verification task. No production secret was read or emitted.

Primary references checked 11 November 2026: [Scheduling and queue-header caveat](https://supabase.com/docs/guides/functions/schedule-functions), [Vault](https://supabase.com/docs/guides/database/vault), [Cron](https://supabase.com/docs/guides/cron), [pg_net](https://supabase.com/docs/guides/database/extensions/pg_net).
