# Hosted migration provenance

Approved shared Supabase project: `wpxeuwknbuxbtkkkmcsm` (Multiple ones / Markov).

The coordinating agent observed these **existing hosted** migration versions:

| Version | Name | Ownership |
|---|---|---|
| `20261109173725` | `create_crumb_clock_waitlist` | Existing marketing history; not authored/reconstructed here |
| `20261109173858` | `restrict_internal_rls_trigger` | Existing marketing history; not authored/reconstructed here |
| `20261111151503` | `crispy_mobile_kernel_v1` | App kernel; applied through the approved connector |
| `20261111151519` | `crispy_mobile_media_billing_v1` | App media/billing; applied through the approved connector |
| `20261111155139` | `crispy_mobile_worker_vault_dispatch_v1` | Vault worker authentication/dispatcher; applied, named processing cron now active with explicit owner approval |
| `20261111155946` | `crispy_mobile_worker_readonly_health_v1` | Purpose-scoped read-only health; applied, worker version 2 deployed |

The two local app migration files now use the exact hosted versions/names. Their original CLI-generated local timestamps (`20261111143554` and `20261111145945`) were superseded when the connector applied them under hosted versions; they are **not separate pending migrations**. No hosted history was repaired, squashed or rewritten to achieve this alignment.

The worker dispatcher was generated locally as `20261111154709` but applied through the connector under actual hosted version `20261111155139`; its local filename now matches the hosted version/name. No history repair was performed. Worker version 1 was deployed by the coordinator.

The read-only health migration was generated locally as `20261111155610`, then applied through the connector as actual hosted version `20261111155946`; its local filename now matches. Worker version 2 with the dedicated health handler was deployed by the coordinator. The coordinator subsequently observed the dedicated read-only health response: HTTP 200, `{ok:true,mode:"heartbeat"}`, no timeout. No user-job processing was invoked. Processing/forced dispatch was rejected by automatic approval review and was not used as verification; see `WORKER_DEPLOYMENT.md` for the dedicated health alternative. The owner explicitly approved **“Activate protected job processing”**. The coordinator activated only `crispy-crust-mobile-job-worker-v1` via `cron.alter_job` and verified `active=true`, schedule `* * * * *`. Its latest observed cron run succeeded, starting `2026-11-11 16:14:00.137931+00`, with `cc_jobs=0`. This verifies the empty-queue scheduler path, not actual user-job, export or account-deletion completion. No hosted history repair was performed.

This directory deliberately does not invent empty placeholder files for the older waitlist migrations. Before using CLI migration up/db push against the complete shared project, obtain the original historical migration SQL from the website repository and/or fetch the authoritative remote migration history into a reviewed scratch checkout. The installed CLI v3's `supabase migration fetch --help` documents `--remote=<ref|branch|url>`; use the explicitly selected approved project and scoped credentials. Review fetched files before adopting them into the shared history.

Do not use `migration repair`, an empty baseline, or a guessed timestamp to silence a history mismatch. Do not run a blind db push from an app-only subset of a shared project's history. The two application schemas can be verified locally with `npm test` without linking a project or changing hosted history.
