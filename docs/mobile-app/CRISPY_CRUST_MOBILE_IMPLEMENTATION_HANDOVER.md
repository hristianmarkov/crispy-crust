# Crispy Crust mobile — implementation handover and remaining build plan

**Handover date:** 11 November 2026 (Europe/London). **Repository:** https://github.com/hristianmarkov/crispy-crust. **Development branch:** `feat/flutter-mobile-app`. **Draft PR:** https://github.com/hristianmarkov/crispy-crust/pull/3.

This is the continuation document beside [the original complete build plan](CRISPY_CRUST_BUILD_PLAN.md). Read both. The original describes the intended product; this document describes the actual implementation, live infrastructure, verification and work left. **The whole product is not finished or ready for public launch.** Continue the full scope locally; do not mistake successful compilation or a source adapter for accepted product functionality.

## 1. Start here: exact state being handed over

- The website is being converted to marketing-only content. Those changes are in this branch; the live website has not been redeployed. No Flutter Web consumer product is intended.
- The Flutter phone app, pure Dart engines, catalogue, local database, cloud command backend, native companions and CI are implemented to the depths listed below. Several full-plan journeys remain unfinished.
- The original planning work is already on main. **The implementation is in this branch/PR, not main.** Check out this branch to obtain the work. No implementation merge or store submission has been performed.
- The last fully observed source checkpoint before this handover is `67027f14474cc97a7b75545434b5fddeab180d3c` (CI12). The final handover commit also includes the Wear artifact-location correction. Inspect the final diff and its fresh CI results.
- Legacy ZIPs in this documentation directory are historical planning exports. They do not contain the current implementation. Git is the authoritative handover.
- No private provider/store keys have been committed. Public Supabase client configuration is intentionally checked in. Do not replace it with a service-role key.

## 2. What has actually passed

CI12: https://github.com/hristianmarkov/crispy-crust/actions/runs/43056888235 at `67027f1`.

| Check | Observed result | Limit |
|---|---|---|
| Backend TypeScript, database/API/provider/worker tests | PASS; 55 tests | Some managed services/extensions are represented by isolated stubs; see real hosted evidence below |
| Hosted API privacy smoke | PASS | Rejects missing/invalid auth, unapproved origins, anonymous private Data API access and unauthenticated worker access; not signed-in acceptance |
| Domain engine tests | PASS; 50 synthetic cases | Synthetic fixtures are not validated baking methods |
| Content model validation | PASS; 11 tests | Schema validity does not establish kitchen/editorial validation |
| Flutter analysis and app/persistence tests | PASS in CI12; 119 tests | Earlier CI11 had 114 pass/5 fail, all five test-harness failures were corrected |
| Unsigned iOS build and native Swift companion checks | PASS in CI12 | Includes embedded watch/widget targets; no signing, installation or physical pairing acceptance |
| Android phone debug APK compilation | PASS in CI12 | Build success does not establish device runtime behavior |
| Wear OS debug APK compilation | PASS in CI12 | Same limitation |
| Android phone/Wear identity verification and artifact upload | FAIL in CI12 after both compilations | Actual failure: No verified signing certificate in the phone APK (certificate-output parser found no match). Separately, the old Wear output path is wrong. Handover includes the path correction; certificate parsing/signing still needs investigation and rerun |
| Marketing website typecheck/build/browser checks | Previously PASS, 15 browser tests | Not redeployed; publication dependencies remain |
| Actual Flutter screen capture | PASS, four PNGs uploaded | Captures were generated; no claim of complete human visual/accessibility acceptance |

The current cloud workspace could not fetch Flutter's Dart SDK from `storage.googleapis.com`, so executable Flutter verification used GitHub-hosted runners. This does not prevent local continuation with the pinned official Flutter SDK. Syntax parsing alone was never treated as Flutter execution.

## 3. Local checkout, tools and first commands

```sh
git clone https://github.com/hristianmarkov/crispy-crust.git
cd crispy-crust
git switch feat/flutter-mobile-app
```

Use Flutter **3.47.9**, matching `.fvmrc`; the app requires Dart >=3.13 and Flutter >=3.47. Commit-resolved `pubspec.lock` files are present for the app and both packages. Use Node 24 for backend checks, Python 3 for native configuration, and JDK 17/Android SDK including API 37 for Android. iOS requires macOS, Xcode, CocoaPods 1.16.2 and xcodeproj 1.27.0. The generated native runners are reproducible bootstrap output, not missing handwritten app logic.

From the repository root:

```sh
bash mobile/scripts/bootstrap.sh
(cd mobile/apps/mobile && flutter pub get)
(cd mobile/apps/mobile && dart run flutter_launcher_icons)
(cd mobile/apps/mobile && flutter run --dart-define-from-file=../../config/development.json)
```

On macOS install the pinned Ruby gems before bootstrap, which embeds Apple targets:

```sh
gem install cocoapods -v 1.16.2 --no-document
gem install xcodeproj -v 1.27.0 --no-document
```

Bootstrap creates missing iOS/Android/Linux runners without replacing app source or pubspec, configures permissions/native bridges, and copies `mobile/content/catalogue.json` into app assets. Re-run after changing canonical content or native configuration. Linux exists for development/tests, not a promised consumer platform. Do not run `flutter create .` over this project or overwrite the hand-authored configuration.

Verification, each command from the repository root:

```sh
(cd mobile/packages/baking_domain && dart pub get && dart test)
(cd mobile/packages/content_models && dart pub get && dart test)
(cd mobile/backend && npm ci && npm run typecheck && npm test)
(cd mobile/apps/mobile && flutter analyze --no-fatal-infos)
(cd mobile/apps/mobile && flutter test --concurrency=1 --timeout=60s --reporter=expanded)
(cd mobile/apps/mobile && flutter build apk --debug --dart-define-from-file=../../config/development.json)
(cd mobile/apps/mobile/android && ./gradlew :wear:assembleDebug)
python3 mobile/scripts/verify_android_identity.py
```

On macOS also run the unsigned iOS build and Swift tests shown in `.github/workflows/mobile.yml`. Signing is an owner setup task, not supplied by an unsigned artifact. The final Android verification must inspect the actual built packages/certificates, not merely source IDs.

## 4. Code map and how the pieces work together

| Location | Responsibility / continuation notes |
|---|---|
| `mobile/apps/mobile/lib/main.dart` | Bootstrap, theme, local store, native reminder/companion reconciliation and cold-start routing |
| `lib/data/app_store.dart` | AppRecord/AppStore contract, immutable JSON projection and revision identity |
| `lib/data/local_database.dart` | Drift SQLite tables and durable record/event/outbox/preference/cursor storage |
| `lib/data/local_store.dart` | Transactional writes, actual feeds, bake acceptance/completion, journal snapshots, archives/reset and private media cleanup |
| `lib/data/planning_adapter.dart` | Authored recipe graph conversion, availability/reservations, forward/backward solving and conservative rejection |
| `lib/data/sync_client.dart` | Explicit account/kitchen-bound sync, retry IDs, CAS conflict preservation, reviewed server adoption and local-only conflict copies |
| `lib/screens/main_screen.dart` | Five tabs, recipe browsing, starter/bake details, observations, kitchen/settings/pantry/learning/privacy and route integration; large file worth carefully splitting later |
| `lib/screens/plan_review_screen.dart` | Read-only proposed schedule; acceptance rechecks exact candidate before persistence |
| `lib/screens/private_recipe_editor.dart` | Multiple physical ingredients/preferments, explicit timed sequential steps/resources, private provenance and incomplete non-runnable drafts |
| `lib/screens/formula_tools_screen.dart` | Exact physical formula, baker percentages, target mass and feed-build tools |
| `lib/screens/starter_insights_screen.dart` | Explicit feed-linked evidence, comparable peaks, empirical windows, manual jar checks and care mode |
| `lib/screens/production_screen.dart` | Experimental production quantities/loads, capacities/changeovers/pickup windows, exact shopping/cost/CSV and recorded yield |
| `lib/screens/journal_book_screen.dart` | Selected PDF/book data review, comparisons, experiments and missing-data-aware charts |
| `lib/screens/cloud_workspace_screen.dart` | Authenticated kitchens/members/invites, shares, community, coach/import/job and deletion request interfaces |
| `lib/screens/sync_conflicts_screen.dart` | Local/server review, explicit safe server adoption and private retained copies; unsafe physical conflicts require manual reconciliation |
| `lib/screens/subscription_screen.dart` | Real configured offerings, localized store prices, restore/manage and server verification |
| `lib/screens/probe_screen.dart` | Point-of-use permission, bounded BLE ESS scan, selected role/calibration/stale reading and explicit save |
| `lib/services_screen.dart` | Optional account, explicit sync consent, calendar import, reminder/companion choices, export and device/subscription routes |
| `lib/platform/` | Secure Auth/PKCE, media, bounded PDF generation, billing SDK, notifications, calendar, sharing, BLE and companion adapters |
| `mobile/packages/baking_domain` | Pure Dart exact arithmetic, formula/feed calculations, graph scheduling/resources, event reducers, starter estimates, comparisons/costs/production |
| `mobile/packages/content_models` | Typed parser and strict schema/publication validation |
| `mobile/content` | Canonical recipe/lesson/guidance drafts; copy via bootstrap |
| `mobile/backend/sql` and `supabase/migrations` | Tenant commands/RLS, roles, reservations, jobs, moderation, private media, billing and purpose-scoped worker authorization |
| `mobile/backend/functions/app-api` | Authenticated router/runtime and provider/deletion/job adapters; caller JWT retained for RLS commands |
| `mobile/backend/functions/job-worker` | Separate protected processing route and purpose-scoped read-only health handler |
| `mobile/backend/functions/revenuecat-webhook` | Authorization plus raw-body HMAC verification and server-side subscriber reconciliation |
| `mobile/native` and `mobile/scripts` | Apple/Wear native sources, runner patching/embedding, build identities and artifact verification |
| `.github/workflows/mobile.yml` | Independent backend, Flutter, Android and macOS checks; artifacts and dependency lock logging |
| `docs/mobile-app/brand-assets` | Original brand exploration, logos, fonts/license files and screen references |

Normal local operation: user action → validated store command → SQLite event/projection/outbox transaction → listeners/UI → optional native reminders/companion snapshot. A cloud account does not itself upload records. Explicit sync binds the local namespace to the selected identity/kitchen. Backend mutations verify Auth, membership/role, expected revision and operation identity. Privileged provider adapters run only inside their checked server paths.

Critical boundaries: timer expiry is not dough readiness; watch acknowledgement is not physical completion; a photo is not consent to upload/analyse; an estimate is not a safety decision; a stored recipe draft is not a reviewed method; a frontend entitlement claim is not payment proof.

## 5. Exhaustive requirement continuation ledger

The F numbers refer to the original build plan. Every row below has remaining work; implemented source is not a claim of full requirement acceptance.

| Requirements | Implemented source | Remaining source work and acceptance |
|---|---|---|
| F01–F04 | Five-tab navigation; Today with named running/overdue timers; multiple starters, lineage/offshoot fields, actual feed/mass accounting, history/correction notes; per-jar manual check reminders and care-mode changes that cancel only that jar's reminders | Rich priority/pinning queue; reviewed new-culture/maintenance/revival guidance; starter demand/retained-mother reconciliation; correction-driven mass/inventory reconciliation; complete onboarding and daily-care scenarios |
| F05–F06 | Private manual/photo observations; explicit feed links and confirmed historical conditions; starter rise history/chart; comparable confirmed-peak count and conservative empirical check window only with sufficient history; no invented fallback window | Calibrated guided capture sequences and time-lapse; independent estimator calibration; reviewed broad care envelopes and troubleshooting; physical camera/storage/permission acceptance |
| F07–F10 | Deterministic forward/backward graph solver, availability/calendar busy blocks, cooling, resource reservations and conflict rejection; readable schedule preview before acceptance, with recheck on save; separate production load scheduling | Multiple-candidate comparison; explicit oven/mix/in-progress anchors; IANA kitchen timezone/DST intention UI; richer vessel/pan/fridge configuration; complete combined-resource/transition fixture and real-kitchen acceptance |
| F11–F12 | Exact rational formula/feed tools, multiple preferments, target dough mass and scaling calculations; structured private formula editor with starter composition, explicit step durations/dependencies/resources; immutable actuals and interruption records | Full unit/density/substitution review UI; direct calculation-to-recipe workflow; validated load adaptations (ordinary bake planning currently restricts scale above 1×); recipe-supported recovery alternatives with accepted plan/reminder diffs |
| F13–F18 | Live steps and explicit actual completion/backdating; durable independent deadlines, Today visibility and native reminder adapters; read-aloud/keep-awake adapters; manual/photo observations and point-of-use BLE probe screen; native widget/Live Activity/watch bridges and cold-start notification routing; text technique help | Complete timer centre/snooze/missed-alert handling and quiet-hour rules; confirmed voice logging; rich per-step technique media; foreground camera monitoring; real OS lifecycle/permission/reboot and named probe/watch compatibility tests; signed companion/device acceptance |
| F19–F24 | 24 original experimental recipe drafts; typed catalogue validators; searchable recipes; editable private ingredient/method copies and incomplete drafts that expose no runnable graph; constrained cloud import source; 18 text lessons/practice records; pantry/shopping/discard records; local exports, responsive controls and text scaling | Reviewed kitchen trials and source/media rights; authentic technique videos/captions/left-handed views; course/resume journeys; complete import-result review/save integration and photo/OCR flow; substitutions/volume/units; inventory consumption and aggregate shopping integration; full accessibility evaluation |
| F25–F28 | Automatic immutable journal snapshots and outcomes; Bake Again routes through review using the pinned formula; missing-data-aware comparisons/charts and experiment records; selected local recipe-book PDF/data preview/share/print with explicit optional photos/notes; portable archive including private media; selected-context cloud coach request UI | Final PDF/media/platform acceptance; complete outcome/tag/step-note workflows; grounded/vision coach result review and integration, validated response quality and reviewed source coverage; independently reviewed experiment guidance |
| F29–F31 | Revision-checked selected-field share creation/revocation; household invitations/members/roles/ownership transfer; moderated post/comment/follow/report/block commands and consumer UI; private staff-role/MFA backend rules | Full attributed recipient-copy/app-link/install journey; accessible object pickers replacing diagnostic IDs/JSON; shared tasks/acknowledged handoffs and physical-action reconciliation; bake-along/group/challenge workflows; report/appeal status; separate private staff operations application and staffed moderation |
| F32 | Connected production workspace: named products/pickup windows, explicit experimental load assumptions, separate loads, cooling/resource/oven-transition checks, acceptance recheck, recorded actual yield, exact demand, user-price cost estimates and pack-list CSV | Full custom-recipe/production integration, configurable currencies (current production screen uses GBP), polished labels/printing and batch execution/journal handoff; real load/equipment/yield trials; complete traceability and production scenarios |
| F33–F35 | Local-only mode; secure opt-in account source and OAuth state refresh; separate explicit sync consent/account binding; conflict list/version review/export and constrained server-version resolution retaining local evidence; private local media; archive/export/import/reset and account-deletion request UI; real RevenueCat offering/purchase/restore source with server verification, no invented products or local entitlement unlock | Manual reconciliation workflow for conflicting physical feeds/completions/inventory; complete multi-device/cloud-media acceptance; hosted Auth/email/OAuth/provider setup and deletion/export drills; active worker scheduling only after accepted verification; quiet hours/pins/granular service controls; retention/support/store disclosures; configured products and store sandbox acceptance |
| F36 | CI, versioned content/migrations, database/API tests, provider adapters and operational role/command contracts; hosted API and protected worker function deployments | Full private editorial/moderation/support tooling; queue/incident monitoring; backup/restore and key-rotation drills; operational ownership/capacity; all final checks green and the complete coordinated release gate |


## 6. Live Supabase state — preserve this when continuing

**Owner-approved exception to the original separate-project architecture:** use the existing CrispyCrust project in **Multiple ones / Markov**, project ID **wpxeuwknbuxbtkkkmcsm**, region **eu-central-1**. The separate free-project creation failed due to quota; the owner explicitly chose reuse. Project URL: `https://wpxeuwknbuxbtkkkmcsm.supabase.co`.

Existing `crumb_clock_waitlist`, `crumb_clock_rate_limits` and `crumb-clock-waitlist` were preserved. Last observed waitlist count: zero. App state uses `cc_` tables and `app_private`, with 19 public app tables protected by RLS and private `kitchen-media` storage. Security advisors reported only the two pre-existing informational no-policy notices on the legacy deny-all tables; no new app finding was observed. This is shared infrastructure, not complete project isolation.

Applied app migration versions (already live; do not apply again):

1. `20261111151503_crispy_mobile_kernel_v1`
2. `20261111151519_crispy_mobile_media_billing_v1`
3. `20261111155139_crispy_mobile_worker_vault_dispatch_v1`
4. `20261111155946_crispy_mobile_worker_readonly_health_v1`

Local filenames match the actual hosted versions. Older hosted waitlist history is external to this app migration subset. **Do not blindly db push, create guessed empty baselines or repair history.** Read [hosted migration provenance](../../mobile/backend/HOSTED_MIGRATIONS.md) before linking CLI operations.

Deployed functions: **app-api v2**, **job-worker v2**, **revenuecat-webhook v1**. Gateway JWT verification is disabled deliberately because each function implements its own authentication: Auth-token verification on app API; scoped worker authorization; configured webhook authorization plus HMAC. Preserve those checks when modifying entrypoints. Deploy all relative module dependencies, including the worker's `authorize.ts` and `handler.ts`, not just index.ts.

The owner explicitly approved activating protected job processing, including requested export/deletion jobs. Only cron **crispy-crust-mobile-job-worker-v1** is active, every minute. Its observed scheduled run at **16:14 London time / UTC** succeeded with **zero jobs**. This verifies scheduling, not successful completion of a real user deletion/export. No app profiles or jobs existed at the relevant preflight.

Long-lived HMAC signing material was generated inside Vault and never returned. Outgoing requests use two-minute, one-use capabilities. Dedicated `/job-worker/health` uses a different signed purpose and cannot claim jobs. Its pg_net request ID 1 returned HTTP 200 `{ok:true,mode:heartbeat}` and consumed the nonce. Automatic review originally rejected forced dispatch because it could execute deletion jobs; the read-only alternative was used. Do not use forced dispatch as a heartbeat workaround.

Read [worker operations](../../mobile/backend/WORKER_DEPLOYMENT.md) and [backend implementation/deployment](../../mobile/backend/README.md). Actual provider jobs, storage upload/deletion, real account erasure, backups and restore drills remain acceptance work. Worker throughput is one claimed job per dispatch; measure queue latency/capacity before enabling production services.

## 7. Access, secrets and pending owner setup

[OWNER_SETUP.md](../../mobile/OWNER_SETUP.md) contains the concrete owner steps. The following are still unresolved:

- Supabase Auth allowlist `app.crispycrust://auth/callback`; email OTP template exposing `{{ .Token }}`; production sender/deliverability and Apple/Google OAuth. The user was asked to complete the redirect/template setup; no completion was observed at handover. The connector cannot configure these and browser control failed due to unavailable native accessibility provider.
- Apple Developer/App Store Connect and Google Play access, agreements, signing, real device testing, application links and release credentials. Phone identity is `app.crispycrust.mobile`; Apple companions are `.watch` and `.widgets`. Preserve configured app-group entitlements. Phone and Wear need matching package IDs and signing certificates.
- RevenueCat products, commercial boundaries, prices/markets/trials, restore policy and sandbox lifecycle. Public client build keys: `REVENUECAT_IOS_PUBLIC_SDK_KEY` and `REVENUECAT_ANDROID_PUBLIC_SDK_KEY`. Server names are in `mobile/backend/.env.example`; never copy server keys into dart defines.
- RevenueCat webhook needs both configured Authorization and current provider HMAC signing enabled. Current official HMAC documentation was checked; legacy Authorization-only setup will fail closed. No purchase or production billing acceptance was performed.
- `AI_JOBS_ENABLED`, `IMPORT_JOBS_ENABLED`, `IMAGE_JOBS_ENABLED`, `MEDIA_UPLOADS_ENABLED` require deliberate server configuration and acceptance. No enabling/secrets were configured by this execution. Missing provider configuration must remain visibly unavailable, not simulate success. Approve model/cost/privacy settings before adding `OPENAI_API_KEY`/`COACH_MODEL`.
- Recipe URL import requires `IMPORT_ALLOWED_HOSTS` and reviewed egress controls. Do not remove SSRF checks or claim unrestricted arbitrary URL safety.
- Legal entity/privacy controller, real support/deletion contact, launch countries/languages/age policy and service ownership. These were not specified by the original supplied vision. Do not infer them from the GitHub author or manufacture addresses/prices.
- Real kitchen trials/editorial review, authentic technique footage/captions, media rights, named probe/watch/phone hardware and operational staffing.

The 24 recipe methods and 18 text lessons are experimental drafts. No reviewed broad starter-care envelope or validated recovery branch has been fabricated. Five comparable peaks is an initial product threshold, not a statistically calibrated guarantee.

## 8. Concrete local continuation work orders

These are engineering work orders for the same single release, not staged public launches.

1. **Reproduce the handed-over baseline.** Read this document, original plan, owner setup, backend/native READMEs and requirement traceability. Check final branch status and Actions. Investigate the actual `No verified signing certificate` failure using `apksigner verify --verbose --print-certs` on the built phone APK; distinguish a changed output format from a signing defect without weakening verification. Re-run identity/artifact checks with the included corrected Wear metadata lookup. Preserve all passing tests and exact locks.
2. **Close remaining everyday local workflows.** Implement starter demand/retained mother/consumption reconciliation, correction-led inventory transactions, daily priorities/pins and complete onboarding/care journeys. Reconcile ambiguous physical evidence explicitly; never auto-duplicate a feed or step.
3. **Complete planning experience.** Candidate comparison, explicit start/oven/in-progress intentions, IANA timezone and DST ambiguity handling, common vessel/pan/fridge capacities, complete resource transitions and accepted replan diffs. Preserve pinned recipe versions, completed actuals and reminders. Unsupported recipe recovery must remain unsupported until reviewed evidence exists. Replace current >1x ordinary-bake restriction only with tested load models.
4. **Complete recipe and learning journeys.** Supported unit/density conversions with provenance, substitutions/allergens, import/OCR review and save flow, calculations into actual private recipes, course/resume paths, real technique media. Keep incomplete drafts non-runnable. Production must support private recipes and chosen currencies rather than hardcoded GBP.
5. **Complete active kitchen/device use.** Timer centre, snooze/missed-alert/quiet-hour handling, confirmed voice logging, contextual techniques and validated foreground monitoring. Test permission denial, process kill, reboot, timezone change, stale sensors and watch pairing. Manual use must always work.
6. **Finish journals/production.** Outcome tags/step notes, comparable experiment interpretation, calibrated charts, polished book/label printing, batch execution and journal traceability, combined shopping/inventory consumption. PDF limits currently bound selected text/rows/photos/pages/output size; preserve those checks and selected-data privacy.
7. **Replace diagnostic cloud UX.** Object pickers and readable states instead of raw IDs/JSON; complete imported recipe/coach result review, attributed recipient copies and install/app-link journeys, shared handoffs, group/bake-along/challenge/report/appeal workflows. Server role enforcement and recent-auth requirements remain authoritative.
8. **Implement private operational tools.** Editorial publishing/version control, moderation/support/appeals and MFA/role operations, incident/queue monitoring, audit visibility, backups/restore and key rotation. Consumer controls are not a complete staff application.
9. **Run real hosted and store acceptance.** Opt-in sync/account switch/conflict recovery, multiple kitchens/invites/revocation/owner transfer, chosen private media, billing lifecycle, AI/import budgets and failures, exports/deletions and retained shared data. Do not use real customer data as disposable test fixtures.
10. **Validate content and full usability.** Execute the original plan's kitchen fixtures and participant scenarios, including beginners, experienced bakers, production users, large text and screen readers. Preserve evidence and fix failures; synthetic tests cannot substitute for this.
11. **Prepare one coordinated launch.** Complete the full requirement matrix, legal/store disclosures, signed release builds/listings, verified support/deletion route, capacity/monitoring and rollback. Publish marketing changes and real store links together with the agreed release behavior. Do not publish a partial app merely because one build is green.

## 9. Implementation traps already discovered

- Cloud sync pull uses `id`, not `entity_id`; the wrong key previously collapsed multiple records. Regression coverage exists.
- Custom text-only methods with zero durations were false runnable graphs; the structured editor now stores incomplete drafts with no executable steps.
- Previewing a schedule must not reserve it. Accepting recomputes constraints and checks `expectedSchedule`; changes reject rather than silently move the displayed plan.
- Bake Again must use the pinned snapshot through the planner, not today's catalogue version or bypass review.
- Production reservations must participate in ordinary bake scheduling and vice versa. Packed/abandoned runs release reservations.
- Auto discard records need `grams`; compatibility `quantity` is retained. Unknown data must not display as measured zero.
- Starter reminders are jar-specific; pausing/travel cancels only that jar's timers. An observation is never inferred to be a feed.
- A helper LocalAppStore owns/closes its database on dispose; tests must not dispose it before final sync assertions.
- Flutter lazy lists require scrolling controls into a hittable viewport and pumping after scroll. Never hide failures using `warnIfMissed:false` or removing assertions.
- Dialogs awaiting a user choice must not keep an indeterminate background spinner that prevents settling.
- Apple embed phases and target product names matter; preserve the tested real-Xcodeproj ordering helper.
- Android API 37 is required by the pinned plugins. The modern AGP/Kotlin DSL replaces deprecated `kotlinOptions`/legacy accessors. Flutter relocates Wear outputs under `apps/mobile/build/wear`; use metadata, not guessed APK filenames.
- Native notifications use the plain `ic_notification` resource name. Cold-start notification details are handled once, including late router binding.
- Physical user operations, deletion or entitlement changes need trustworthy confirmation/identity; no UI flag can override server facts.

## 10. Final handoff checklist for the next agent

Use this branch, not a ZIP or main-only checkout. Review the final commit and unverified changes, then run the commands above. Keep the implementation ledger current, record exact tested SHAs, and distinguish source, local tests, hosted acceptance and physical acceptance. Obtain required credentials through secure provider/CI settings. Do not ask the owner again for already-approved shared-project use or named worker activation. Preserve the existing waitlist and avoid paid provisioning without an agreed cost. Do not claim completion while the remaining implementation and acceptance rows remain open.
