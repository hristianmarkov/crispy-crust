# Crispy Crust mobile workspace

Flutter iOS/Android implementation of [the approved specification](../docs/mobile-app/CRISPY_CRUST_BUILD_PLAN.md). This workspace is under active implementation. **It is not a completed, validated or store-ready release.** The single-launch contract remains in force; no partial public release is proposed.

## Run locally

Install Flutter **3.47.9** (pinned in `.fvmrc`) with its matching Dart SDK. Android needs the supported Android SDK/JDK; iOS needs macOS/Xcode/CocoaPods. Run from the repository root:

```sh
bash mobile/scripts/bootstrap.sh
cd mobile/apps/mobile
flutter pub get
dart run flutter_launcher_icons
flutter run --dart-define-from-file=../../config/development.json
```

Bootstrap creates missing iOS/Android/Linux runners without overwriting app source or package configuration, applies native permissions/bridges, and copies the canonical content catalogue. The consumer product is not built for Flutter Web. Linux is a development/test surface.

The checked-in development configuration targets the owner-approved existing Supabase project. The app uses its own API and namespaced data; it does not call the marketing waitlist. To use another explicitly selected app environment, pass only its public configuration:

```sh
flutter run --dart-define=SUPABASE_URL=https://YOUR-APP-PROJECT.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR-PUBLISHABLE-KEY
```

Never put a service-role key, model key or store/server secret in those values. Cloud initialization happens only after a user chooses Connected services. Account sign-in does not enable library sync. A separate selected-data preview/consent enables the personal-library upload. The sync namespace is bound to one user/kitchen and rejects a different account binding. Sync remains a manual, one-shot action. Conflict review retains local evidence; conflicting physical feeds/completions still need manual reconciliation. Hosted multi-device acceptance remains pending.

## Verification

```sh
cd mobile/packages/baking_domain && dart pub get && dart test
cd mobile/packages/content_models && dart pub get && dart test
cd mobile/backend && npm ci && npm run typecheck && npm test
cd mobile/apps/mobile && flutter pub get && flutter analyze --no-fatal-infos && flutter test
```

Run each command from the repository root (or use separate terminal sessions). GitHub workflow `Mobile verification` runs the package tests, database/API tests, widget/persistence tests, Android debug build, Wear OS build and unsigned iOS/companion builds. Artifacts contain successful build outputs and actual Flutter-rendered screen captures when the corresponding checks pass. Android CI also checks phone/Wear application IDs and signing-certificate agreement in the actual APKs. An unsigned iOS app is not installable distribution; developer signing and store configuration are still required.

At historical commit `2e46182`, unsigned iOS/native companion checks and hosted backend privacy smoke checks passed; the app run had 54 passing and 4 failing tests. The fixes and additional integrations in `d252e35` still need their own passing hosted run. Check [PR #3](https://github.com/hristianmarkov/crispy-crust/pull/3) and [the implementation ledger](IMPLEMENTATION_STATUS.md) for current evidence. This workspace cannot currently fetch Flutter's Dart SDK from `storage.googleapis.com`, so hosted checks are the available Flutter execution evidence.

## Code map

- `apps/mobile`: five-tab Flutter app; Drift SQLite/event/outbox persistence; schedule preview and acceptance recheck; structured private recipe editor and exact formula/feed tools; starter evidence/manual jar checks; production load/reservation/cost/CSV workspace; journal comparison and selected local PDF/print/export; explicit account/sync/conflict/service/subscription screens; native adapters.
- `packages/baking_domain`: exact rational formula/feeding/scaling, recipe graphs, bounded schedule/resource solver, immutable event reducer, conservative starter estimates, comparisons/cost/shopping and production composition.
- `packages/content_models`: strict typed catalogue parser, schema and publication validator.
- `content`: 24 original **experimental drafts**, 18 text lessons and source-linked safety guidance. No kitchen-testing claim or invented instructional photos/videos.
- `backend`: app-namespaced sources in the owner-approved shared Supabase project, migrations, tenant policies/commands, API/protected job worker, private sharing, household/community/moderation and provider adapters. Read its README for exact deployment state and remaining gaps.
- `native`: Apple widget/Live Activity/watch and Wear OS sources. Read its README for supported capabilities, signing and physical-device gates.
- `scripts`: reproducible runner/configuration/embedding tools.

## Data and safety rules

Critical writes commit records, audit events and outbox entries atomically before success is shown. The planner must reject conflicts rather than silently ignore absence or equipment. App-imported/manual recipes remain experimental. No content draft has approved adaptive cold-rest branches; the app cannot manufacture a tested rescue method. Timer expiry is not biological readiness. Photos are private by default; attaching one does not upload it or authorise AI analysis.

Cloud transport and managed storage encryption are not end-to-end encryption. Native notifications are best effort and cannot substitute for supervising an oven. Watch acknowledgement is distinct from completing a physical step. Device compatibility and food guidance need actual evidence.

## External setup and release gates

The selected Supabase account is **Multiple ones**, organisation **Markov**. After a separate project hit the free-project limit, the owner explicitly authorised using the existing CrispyCrust project (`wpxeuwknbuxbtkkkmcsm`). App data uses `cc_` tables and `app_private`; the legacy waitlist tables/function are preserved. The kernel/media migrations and Vault worker migration (`20261111155139`) have been applied. Initial hosted checks verified RLS on the 19 public app tables, a private media bucket and no new app security-advisor findings at that checkpoint. `app-api` v2 and `job-worker` v1 are deployed, but the named worker cron is inactive; automatic approval review blocked forced dispatch verification. A read-only health alternative is being prepared. Deployment is not proof that export/deletion jobs complete or that Auth/provider flows work. `config/development.json` contains only public client identifiers. Never use it as an authorisation boundary or put server secrets there.

Source work also remains: supported in-progress replanning/recovery, timezone/DST and additional planner anchors, full timer/quiet-hour controls, guided camera sequences, voice logging, substitution/unit flows, complete import/household/community journeys and the private operations app. These are part of the original full-launch contract.

Other external gates include Apple/Google organisation accounts/signing, OAuth/email setup, privacy/support contact and markets, production model/provider configuration and spend approval, final commercial products, physical iOS/Android/watch/probe checks, recipe trials/media rights, and moderation/support ownership. See [IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md). Unconfigured providers must fail visibly; no fake successful purchase, upload or analysis is acceptable.

Subscription source uses `REVENUECAT_IOS_PUBLIC_SDK_KEY` and `REVENUECAT_ANDROID_PUBLIC_SDK_KEY` only for the platform's public SDK key. Server RevenueCat credentials remain server-side. The screen obtains actual configured offerings/store prices and requests authenticated server verification; missing configuration never invents products, prices or entitlements. Store sandbox tests and commercial approval are still required.
