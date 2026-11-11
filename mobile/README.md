# Crispy Crust mobile workspace

Flutter iOS/Android implementation of [the approved specification](../docs/mobile-app/CRISPY_CRUST_BUILD_PLAN.md). This workspace is under active implementation. **It is not a completed, validated or store-ready release.** The single-launch contract remains in force; no partial public release is proposed.

## Run locally

Install Flutter **3.47.9** (pinned in `.fvmrc`) with its matching Dart SDK. Android needs the supported Android SDK/JDK; iOS needs macOS/Xcode/CocoaPods. Run from the repository root:

```sh
bash mobile/scripts/bootstrap.sh
cd mobile/apps/mobile
flutter pub get
dart run flutter_launcher_icons
flutter run
```

Bootstrap creates missing iOS/Android/Linux runners without overwriting app source or package configuration, applies native permissions/bridges, and copies the canonical content catalogue. The consumer product is not built for Flutter Web. Linux is a development/test surface.

To connect an approved **app** backend (not the marketing waitlist), pass public configuration:

```sh
flutter run --dart-define=SUPABASE_URL=https://YOUR-APP-PROJECT.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR-PUBLISHABLE-KEY
```

Never put a service-role key, model key or store/server secret in those values. Cloud initialization happens only after a user chooses Connected services. Account sign-in does not enable library sync. A separate selected-data preview/consent enables the personal-library upload. The sync namespace is bound to one user/kitchen; switching accounts cannot merge or expose a previous account's library.

## Verification

```sh
cd mobile/packages/baking_domain && dart pub get && dart test
cd mobile/packages/content_models && dart pub get && dart test
cd mobile/backend && npm ci && npm run typecheck && npm test
cd mobile/apps/mobile && flutter pub get && flutter analyze --no-fatal-infos && flutter test
```

Run each command from the repository root (or use separate terminal sessions). GitHub workflow `Mobile verification` runs the package tests, database/API tests, widget/persistence tests, Android debug build, Wear OS build and unsigned iOS/companion builds. Artifacts contain successful build outputs and actual Flutter-rendered screen captures when the corresponding checks pass. An unsigned iOS app is not installable distribution; developer signing and store configuration are still required.

## Code map

- `apps/mobile`: five-tab Flutter app, local Drift SQLite persistence, event/outbox log, archive handling, explicit cloud services and native adapters.
- `packages/baking_domain`: exact rational formula/feeding/scaling, recipe graphs, bounded schedule/resource solver, immutable event reducer, conservative starter estimates, comparisons/cost/shopping and production composition.
- `packages/content_models`: strict typed catalogue parser, schema and publication validator.
- `content`: 24 original **experimental drafts**, 18 text lessons and source-linked safety guidance. No kitchen-testing claim or invented instructional photos/videos.
- `backend`: isolated Supabase project sources, migrations, tenant policies/commands, API/job worker, private sharing, household/community/moderation and provider adapters. Read its README for deployment and remaining gaps.
- `native`: Apple widget/Live Activity/watch and Wear OS sources. Read its README for supported capabilities, signing and physical-device gates.
- `scripts`: reproducible runner/configuration/embedding tools.

## Data and safety rules

Critical writes commit records, audit events and outbox entries atomically before success is shown. The planner must reject conflicts rather than silently ignore absence or equipment. App-imported/manual recipes remain experimental. No content draft has approved adaptive cold-rest branches; the app cannot manufacture a tested rescue method. Timer expiry is not biological readiness. Photos are private by default; attaching one does not upload it or authorise AI analysis.

Cloud transport and managed storage encryption are not end-to-end encryption. Native notifications are best effort and cannot substitute for supervising an oven. Watch acknowledgement is distinct from completing a physical step. Device compatibility and food guidance need actual evidence.

## External setup and release gates

The selected Supabase account is **Multiple ones**, organisation **Markov**. Its existing CrispyCrust project serves the website waitlist. Creation of a separate app development project was quoted at $0/month but rejected because the owner has reached the two-project free limit. No existing project was paused, deleted or repurposed. New app deployment awaits capacity.

Other external gates include Apple/Google organisation accounts/signing, OAuth/email setup, privacy/support contact and markets, production model/provider configuration and spend approval, final commercial products, physical iOS/Android/watch/probe checks, recipe trials/media rights, and moderation/support ownership. See [IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md). Unconfigured providers must fail visibly; no fake successful purchase, upload or analysis is acceptable.
