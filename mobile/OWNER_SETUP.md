# Owner setup and coordinated-release dependencies

This file records concrete setup the implementation cannot complete with the currently connected tools. It is not a release checklist that replaces the full [implementation ledger](IMPLEMENTATION_STATUS.md). The product still has source work and acceptance work to complete. Keep credentials in the provider's settings or the repository's protected CI secrets, never in chat or client source.

## Existing backend

Use Supabase project **wpxeuwknbuxbtkkkmcsm**, account **Multiple ones**, organisation **Markov**. The owner explicitly approved sharing this project with the website. App objects use `cc_` and `app_private`; preserve `crumb_clock_waitlist`, `crumb_clock_rate_limits` and `crumb-clock-waitlist`.

The four app migrations are applied; their exact versions are in [HOSTED_MIGRATIONS.md](backend/HOSTED_MIGRATIONS.md). `app-api` v2, `job-worker` v2 and `revenuecat-webhook` v1 are deployed. Private media and app-table RLS are configured. Public build identifiers are in `config/development.json`. They do not grant privileged access.

The owner explicitly approved protected export/deletion processing, and the named cron **crispy-crust-mobile-job-worker-v1** is now active every minute. A scheduled run at 16:14 UTC succeeded with an empty queue. The dedicated purpose-scoped health endpoint returned HTTP 200 without job processing. Automatic approval review had rejected forced dispatch; that route was not retried as a heartbeat workaround. Actual user-job/deletion completion remains an acceptance task. See [WORKER_DEPLOYMENT.md](backend/WORKER_DEPLOYMENT.md).

## Supabase Auth and email

In the existing project's Auth settings:

- Add the mobile redirect `app.crispycrust://auth/callback` to the redirect allowlist. Keep the existing marketing configuration intact. The app uses PKCE and checks this exact scheme, host and path.
- Configure email OTP delivery and a template that exposes `{{ .Token }}` for the app's code-entry screen. Confirm current OTP length/expiry/resend settings and test them on a real device. A default development email sender does not establish production deliverability.
- Configure Apple and Google OAuth with the matching provider credentials and Supabase callback URL shown by the provider setup screen. Register actual app identifiers and required signing fingerprints. Test browser cancellation, expired codes, cold-start callbacks, sign-out and account switching.
- Supply a verified production mail sender/domain and its SPF/DKIM/DMARC configuration. Never use a guessed support address.

The connected Supabase tools do not expose these Auth configuration controls. The available desktop/browser automation could not control the browser (missing AT-SPI provider), so these settings have not been changed or verified.

## Apple, Android and companion identities

The phone app identity is **app.crispycrust.mobile** on iOS and Android. Apple companion identifiers are **app.crispycrust.mobile.watch** and **app.crispycrust.mobile.widgets**. Use the app-group/entitlement values in the checked-in native configuration; do not invent different values when signing.

An Apple Developer/App Store Connect team must register the products, approve required agreements and provide scoped signing/build access. Google Play must have the corresponding application, store agreements and signing configuration. Phone and Wear OS packages must have the same application ID and signing certificate for their transport; debug CI checks this in the actual APKs, while release signing and physical pairing remain separate acceptance.

Register universal/app links only after actual Apple team IDs and Android certificate fingerprints are known. Static association files can live on the marketing domain; the website remains promotional.

## RevenueCat and store products

The commercial proposal calls the service tier Pro, but prices, territories, product IDs, paid boundaries and trials are not approved. Decide those before publishing or enabling a paywall. Deterministic local tools and existing records/export remain available.

Configure the Apple/Google products and matching RevenueCat project, subscription entitlement allowlist and restore-transfer policy. For this authenticated-account design, evaluate keeping purchases with their original app user ID. Exercise purchase, restore, renewal, expiry, billing issue, refund and account-switch scenarios in store sandboxes.

Client build configuration contains only public SDK keys:

```text
REVENUECAT_IOS_PUBLIC_SDK_KEY
REVENUECAT_ANDROID_PUBLIC_SDK_KEY
```

Server-side Edge Function settings use the names in `backend/.env.example`: `REVENUECAT_API_KEY`, `REVENUECAT_WEBHOOK_AUTHORIZATION`, `REVENUECAT_WEBHOOK_SIGNING_SECRET`, `REVENUECAT_ENVIRONMENT` and `REVENUECAT_ENTITLEMENT_KEYS`. Enable HMAC signing on the RevenueCat integration and use the deployed `/functions/v1/revenuecat-webhook` endpoint. The server requires the configured Authorization header and the current provider's raw-body signature. A deployed endpoint with missing configuration is unavailable, not a working billing integration.

The mobile client shows actual store offering prices. It does not fabricate products or unlock paid state from local assertions. Purchase access also requires successful server verification.

## Optional cloud services

Provider keys remain server-side. Keep `AI_JOBS_ENABLED`, `IMPORT_JOBS_ENABLED`, `IMAGE_JOBS_ENABLED` and `MEDIA_UPLOADS_ENABLED` disabled until the relevant service, consent, retention, budget and end-to-end checks are ready. The backend README documents the exact variables and adapters.

Approve a specific model and spend cap before setting `OPENAI_API_KEY`/`COACH_MODEL`. Recipe URL import needs an operator-reviewed `IMPORT_ALLOWED_HOSTS` allowlist and egress protection; it is not an unrestricted internet fetcher. A user's photo attachment does not authorise uploading or analysing that photo. Verify private media upload, MIME/size/hash checks, metadata rejection, cancellation and deletion against the real hosted service.

## Content, operations and release

The catalogue contains **24 experimental recipe drafts**, **18 written technique drafts** and sourced guidance pending review. No kitchen validation, original technique film or licensed process-photo catalogue has been fabricated. Record actual trials, equipment/quantity limits, readiness cues, allergens, media rights and editorial approval before publishing them as reviewed content. Recovery branches and care envelopes require that evidence.

Owner inputs still needed include the legal/privacy controller, support/deletion contact, launch countries/languages/age policy, moderation/support ownership and operating capacity. Complete backup/restore, deletion/export, account sharing/revocation, provider failure and incident-response drills. Real phones, watches and named probes are required for lifecycle, permission, pairing and calibration acceptance.

Complete the remaining source work in the implementation ledger, get a full green verification run on the release candidate, perform the planned kitchen/accessibility/usability/device acceptance, and coordinate one full launch. The marketing changes are not yet published; they also need the verified privacy/deletion contact and final store links.
