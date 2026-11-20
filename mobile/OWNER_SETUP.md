# Owner setup and coordinated-release dependencies

This file records concrete setup the implementation cannot complete with the currently connected tools. It is not a release checklist that replaces the full [implementation ledger](IMPLEMENTATION_STATUS.md). The product still has source work and acceptance work to complete. Keep credentials in the provider's settings or the repository's protected CI secrets, never in chat or client source.

## Credentials at a glance

Current provider state is recorded in [Launch status](../docs/mobile-app/LAUNCH_STATUS.md). OpenAI is configured. RevenueCat server verification and signed webhook secrets are saved in Supabase; the sandbox TEST webhook returned 200. Apple credentials/products are connected. Google credentials, scoped permissions, APIs and topic connection are saved, with purchase credentials now shown as valid on 20 November. Catalogue writes remain blocked in the refreshed RevenueCat plan despite the saved app-scoped Manage store presence grant; Android base plans/mappings remain outstanding. Billing stays SANDBOX until owner purchase acceptance. The paywall is published; free/Pro coach allowances are 3/60 questions per calendar month, capped at 20/day.

No additional secret is requested for those completed connections. The owner handles SMTP and native auth/device/connected-service acceptance. Public SDK and PostHog configuration is in the ignored local release file. New builds and uploads are authorized as of 20 November. Apple privacy has been certified and published. Google regional price preview is complete; the RevenueCat plan is blocked by provider credential validation and will need final reviewed approval before apply. Other store declarations remain. Reviewer email is hello@leymora.com; the account was created by the owner and its confirmed email/password presence verified on 20 November. RevenueCat registration requires its first sign-in in the updated native app before a Pro grant can be completed. Standard password sign-in is implemented in local source. Review Pro access remains outstanding. These are setup actions, not missing API keys.
The Android OAuth client for Play-signed installs was created in Google Cloud and added to the Supabase Google provider. All four IDs are present, with the existing Web client first. Test Google sign-in on the Samsung.

- **OpenAI** supplies the server-side `OPENAI_API_KEY` for the coach. Set `COACH_MODEL` in the same Supabase Edge Function environment.
- **RevenueCat** supplies the public iOS and Android SDK keys for the mobile build, plus `REVENUECAT_API_KEY` and `REVENUECAT_WEBHOOK_SIGNING_SECRET` for Supabase. Configure the same webhook Authorization value in RevenueCat and `REVENUECAT_WEBHOOK_AUTHORIZATION` in Supabase.
- **Google and Apple sign-in** use the provider credentials configured in Supabase Auth. Production email OTP uses credentials for the SMTP sender configured in the same project.
- **App Store Connect and Google Play Console** need account access and release signing for store builds. The development build already has the existing Supabase publishable key.
- **Recipe URL import** uses the server's `IMPORT_ALLOWED_HOSTS` setting. It has no separate provider API key.
- **PostHog** uses the Crispy Crust project's public project token and ingestion host in the Flutter build. It does not use a personal API key or a Supabase secret.

## Mobile analytics

Local configuration is ready for [Crispy Crust PostHog project 739160](https://us.posthog.com/project/739160/home). Its public project token and US ingestion host are in the Git-ignored `mobile/config/.env.release.json` as `POSTHOG_PROJECT_TOKEN` and `POSTHOG_HOST`. Pass that file to Flutter with `--dart-define-from-file` for the next build. For CI or another workstation, copy the same values from **Project settings**.

In a configured build, **Kitchen → Data & privacy → Share app usage analytics** is off by default. It controls anonymous events for app open, tab changes, Connected services, and subscription screen views. The app does not send account IDs, app records, notes or photos to analytics. Session replay, surveys and automatic capture are disabled. Analytics consent stays on the device and is excluded from archive restore. Verify opt-in and opt-out on both platforms, confirm events in the correct project, and review retention and store privacy disclosures before release. [PostHog Flutter setup](https://posthog.com/docs/libraries/flutter)

## Step-by-step credential setup

1. In the [Crispy Crust Supabase project](https://supabase.com/dashboard/project/wpxeuwknbuxbtkkkmcsm), open **Authentication → URL Configuration** and add `app.crispycrust://auth/callback` to **Redirect URLs**. The development build already has the public Supabase configuration. Hosted functions receive the Supabase service role credential from the platform.
2. For email codes, enter the mail provider's SMTP host, port, username and password, plus your verified sender address, in **Authentication → SMTP Settings**. Under **Email Templates**, include `{{ .Token }}` in **Magic Link** and **Confirm signup** for the app's code-entry flow. This project also serves the website, so check its existing email flows before saving project-wide template changes. [Supabase SMTP](https://supabase.com/docs/guides/auth/auth-smtp) · [Email templates](https://supabase.com/docs/guides/auth/auth-email-templates)
3. Register the native Google and Apple clients using the steps below. Keep provider secrets in Supabase Auth and put only public OAuth client IDs in the Flutter build configuration.
4. For the coach, create a project API key on the [OpenAI Platform](https://platform.openai.com/api-keys). Add it as `OPENAI_API_KEY` in **Supabase → Edge Functions → Secrets**. Set `COACH_MODEL` to a model enabled for your API project that supports Responses and Structured Outputs. Enable `AI_JOBS_ENABLED=true` when ready to test with a signed-in account. [OpenAI quickstart](https://developers.openai.com/api/docs/quickstart) · [Supabase secrets](https://supabase.com/docs/guides/functions/secrets)
5. For subscriptions, register the iOS and Android apps in RevenueCat and connect the store credentials there. Map the store products to an offering and entitlement. Add the two **public SDK keys** to the app build configuration as `REVENUECAT_IOS_PUBLIC_SDK_KEY` and `REVENUECAT_ANDROID_PUBLIC_SDK_KEY`. For a local build, copy `mobile/config/development.json` to the Git-ignored `mobile/config/.env.release.json`, add the two keys as JSON string properties, and pass that file to Flutter with `--dart-define-from-file`. [RevenueCat SDK keys](https://www.revenuecat.com/docs/projects/authentication)
6. In **Supabase → Edge Functions → Secrets**, add `REVENUECAT_API_KEY` using a RevenueCat server key compatible with the v1 subscriber endpoint, `REVENUECAT_ENVIRONMENT=SANDBOX`, and `REVENUECAT_ENTITLEMENT_KEYS=crispy_crust_pro`. In **RevenueCat → Integrations → Webhooks**, use `https://wpxeuwknbuxbtkkkmcsm.supabase.co/functions/v1/revenuecat-webhook`, choose a random Authorization value, and enable HMAC signing. Store the exact Authorization header value as `REVENUECAT_WEBHOOK_AUTHORIZATION` and the HMAC secret as `REVENUECAT_WEBHOOK_SIGNING_SECRET` in Supabase. [RevenueCat v1 subscriber API](https://www.revenuecat.com/docs/api-v1/customers) · [Webhook setup](https://www.revenuecat.com/docs/integrations/webhooks)

### GoDaddy SMTP and the Google Android client form

- Check the product shown in GoDaddy's Email & Office Dashboard. **Professional Email / Titan** uses `smtpout.secureserver.net`, port `465` (SSL/TLS), the full mailbox address as the SMTP username, and the mailbox password. Use that mailbox address as the sender email in Supabase. A domain registration by itself supplies no mailbox or password. [GoDaddy Professional Email SMTP](https://www.godaddy.com/help/set-up-third-party-plugins-or-websites-using-smtp-settings-42788)
- **Microsoft 365 from GoDaddy** has different SMTP requirements. GoDaddy documents that turning on SMTP Authentication can disable security defaults for the organisation. A separate transactional SMTP sender can deliver app codes while GoDaddy continues receiving regular mail. [GoDaddy Microsoft 365 SMTP authentication](https://www.godaddy.com/help/enable-smtp-authentication-40981) · [Supabase custom SMTP](https://supabase.com/docs/guides/auth/auth-smtp)

### Native Google and Apple sign-in

The Google iOS client and the Apple App ID are registered. The Google public iOS client ID is `781369922375-0ejpib0a7pm74741raqf02fkmpadgua4.apps.googleusercontent.com` and is already in build configuration and Supabase's Google provider. Native Sign in with Apple is enabled on the Apple App ID and in Supabase. App Store Connect asks the Account Holder to review the updated Apple Developer Program License Agreement before submitting apps.

1. In the same Google Cloud project, create or reuse a **Web application** OAuth client. Use its public ID as `GOOGLE_WEB_CLIENT_ID` in the Flutter build. In **Supabase → Authentication → Sign In / Providers → Google**, enable the provider, enter the Web client ID first in the allowed client IDs, and enter its secret there. If Google requests a redirect URI for that client, use the callback displayed by Supabase.
2. Create a separate **Android** OAuth client with package name `app.crispycrust.mobile` and the SHA-1 of the app's actual signing certificate. Register a client for each certificate used to distribute the app, including the Play **app signing** SHA-1 when Play signs it. Add the Android client IDs to Supabase's allowed Google client IDs. The Android SDK gets the Web client ID from the Flutter build.
3. Create a separate **iOS** OAuth client with bundle ID `app.crispycrust.mobile`. Add its public ID as `GOOGLE_IOS_CLIENT_ID` in the Flutter build and include it in Supabase's comma-separated Google client IDs, with the Web ID first. The build configuration may be a copy of `mobile/config/development.json`. Before iOS bootstrap, set `CRISPY_CRUST_BUILD_CONFIG` to the absolute path of that JSON file. Bootstrap derives the required reversed Google URL scheme from the iOS client ID. Pass the same file to Flutter using `--dart-define-from-file`. [Supabase Google sign-in](https://supabase.com/docs/guides/auth/social-sign-in/auth-google) · [Google iOS plugin setup](https://pub.dev/packages/google_sign_in_ios)
4. For **native Apple sign-in on iOS**, enable **Sign in with Apple** for the Apple Developer App ID `app.crispycrust.mobile` and refresh its provisioning profile. In the Supabase Apple provider, enable Apple and include this bundle ID in **Client IDs**. The generated iOS runner already declares the entitlement and the app exchanges the Apple ID token and nonce with Supabase. [Supabase native Apple setup](https://supabase.com/docs/guides/auth/social-sign-in/auth-apple)
5. For the **Apple browser option on Android**, keep the Apple Services ID first in Supabase's Apple **Client IDs** list, include the iOS bundle ID in that list, and configure the Apple OAuth secret and Supabase return URL. Then set `APPLE_BROWSER_SIGN_IN_ENABLED=true` in the Flutter build configuration. Renew the OAuth secret before it expires and keep the signing key in secure storage. The mobile callback `app.crispycrust://auth/callback` already appears in the Supabase redirect allowlist. Test that native iOS and Android browser Apple sign-in restore the same app account. [Supabase Apple OAuth](https://supabase.com/docs/guides/auth/social-sign-in/auth-apple)

## Existing backend

Use Supabase project **wpxeuwknbuxbtkkkmcsm**, account **Multiple ones**, organisation **Markov**. The owner explicitly approved sharing this project with the website. App objects use `cc_` and `app_private`; preserve `crumb_clock_waitlist`, `crumb_clock_rate_limits` and `crumb-clock-waitlist`.

The four app migrations are applied; their exact versions are in [HOSTED_MIGRATIONS.md](backend/HOSTED_MIGRATIONS.md). `app-api` v2, `job-worker` v2 and `revenuecat-webhook` v1 are deployed. Private media and app-table RLS are configured. Public build identifiers are in `config/development.json`. They do not grant privileged access.

The owner explicitly approved protected export/deletion processing, and the named cron **crispy-crust-mobile-job-worker-v1** is now active every minute. A scheduled run at 16:14 UTC succeeded with an empty queue. The dedicated purpose-scoped health endpoint returned HTTP 200 without job processing. Automatic approval review had rejected forced dispatch; that route was not retried as a heartbeat workaround. Actual user-job/deletion completion remains an acceptance task. See [WORKER_DEPLOYMENT.md](backend/WORKER_DEPLOYMENT.md).

## Supabase Auth and email

In the existing project's Auth settings:

- Add the mobile redirect `app.crispycrust://auth/callback` to the redirect allowlist. Keep the existing marketing configuration intact. The app uses PKCE and checks this exact scheme, host and path.
- Configure email OTP delivery and a template that exposes `{{ .Token }}` for the app's code-entry screen. Confirm current OTP length/expiry/resend settings and test them on a real device. A default development email sender does not establish production deliverability.
- Configure Apple and Google using the native setup above. Test account selection and cancellation, expired email codes, cold-start callbacks for redirect flows, sign-out, and account switching.
- Supply a verified production mail sender/domain and its SPF/DKIM/DMARC configuration. Never use a guessed support address.

The hosted project already allows the mobile callback and has Google and native Apple configured. Supabase's email template editor requires custom SMTP first. Add the sender details and then update the OTP templates.

## Apple, Android and companion identities

The phone app identity is **app.crispycrust.mobile** on iOS and Android. Apple companion identifiers are **app.crispycrust.mobile.watch** and **app.crispycrust.mobile.widgets**. Use the app-group/entitlement values in the checked-in native configuration; do not invent different values when signing.

An Apple Developer/App Store Connect team must register the products, approve required agreements and provide scoped signing/build access. Google Play must have the corresponding application, store agreements and signing configuration. Phone and Wear OS packages must have the same application ID and signing certificate for their transport; debug CI checks this in the actual APKs, while release signing and physical pairing remain separate acceptance.

Register universal/app links only after actual Apple team IDs and Android certificate fingerprints are known. Static association files can live on the marketing domain; the website remains promotional.

## Apple setup checkpoint · 18 November 2026

- Created **Crispy Crust Baking**, Apple app ID `6836109226`, bundle ID `app.crispycrust.mobile`, SKU `crispy-crust-mobile`, primary language English (U.K.). The owner selected this name after Apple rejected Crispy Crust as already taken.
- Connected dedicated Apple App Store Connect and In-App Purchase keys to RevenueCat iOS app `app3585a9cc83`. Both credentials validated and RevenueCat's API confirms both configured flags are true. Private keys are outside the repository. Preserve their secure backups.
- Created subscription group **Crispy Crust Pro**, ID `22590229`. Monthly product `crispy_crust_pro_monthly` maps to RevenueCat `prodf5ada82d63`. Annual product `crispy_crust_pro_annual` maps to `prod133dffc658`. Both unlock `crispy_crust_pro` and are attached to the existing default offering's monthly and annual packages.
- The owner approved applying the reviewed RevenueCat plan `6bb6a704-6933-4990-9cf1-d243b0f54efe`. It completed successfully. Live store reads confirmed **GBP 2.99 monthly and GBP 29.99 annually**, with 175 priced and available territories for each and availability enabled for future territories. Both return `READY_TO_SUBMIT`. The owner confirmed GBP in the reviewed plan. The plan added blank subscription review screenshots. Replace those with genuine iOS purchase-screen captures before review.
- App distribution is configured for all 175 countries or regions on release. The owner approved a Free app download. Its price wizard was confirmed and the pricing page saved.
- Saved the owner-approved researched subtitle **Sourdough & Bread Planner** and category **Food & Drink**. The owner completed RevenueCat password verification, and the app's RevenueCat Apple notification URL was saved in both Apple production and sandbox notification settings.
- Apple Business showed the Free Apps and Paid Apps agreements active. No agreement was accepted by the agent.
- The owner approved [the researched listing](../docs/mobile-app/APP_STORE_LISTING.md). Its 3,554-character description, 145-character promotional text and 96-character keyword field are saved to the English U.K. listing and were verified exactly after reload. Both Pro subscription products are now saved at Apple service level 1, also verified after reload. App Store keyword volumes/ranks have not been measured. The SEO plugin supplies Google keyword estimates.
- Remaining Apple release work includes support/privacy information and final subscription-benefit disclosures, app privacy and age-rating declarations, genuine iOS screenshots, a signed iOS build and TestFlight purchase/restore verification. The first subscriptions must accompany a new app version for Apple review.
- Android service-account credentials/base plans, the RevenueCat server verification key and signed Supabase webhook remain pending. SMTP remains with the owner. No new Android or iOS binary was built during this store-configuration checkpoint.

## RevenueCat and store products

The [Crispy Crust RevenueCat project](https://app.revenuecat.com/projects/91f95079/apps) has a Test Store catalogue with `monthly`, `yearly`, entitlement `crispy_crust_pro` and offering `default`. Apple monthly/annual products now join those packages, with both Apple credentials configured. The Android app still needs store credentials and base plans. The [paywall draft](https://app.revenuecat.com/projects/91f95079/paywalls/wf7bf6de880e8f4bbe/builder) needs verified policy URLs and an offering association before publication. The RevenueCat webhook still needs setup.

The owner approved monthly 2.99, annual 29.99 and every country, then confirmed the Apple GBP price preview. The Apple products and mappings are recorded in the checkpoint above. Trial and final paid-feature boundaries still need confirmation before publishing a paywall. Deterministic local tools and existing records/export remain available.

Configure the Apple/Google products and matching RevenueCat project, subscription entitlement allowlist and restore-transfer policy. For this authenticated-account design, evaluate keeping purchases with their original app user ID. Exercise purchase, restore, renewal, expiry, billing issue, refund and account-switch scenarios in store sandboxes.

Client build configuration contains only public SDK keys:

```text
REVENUECAT_IOS_PUBLIC_SDK_KEY
REVENUECAT_ANDROID_PUBLIC_SDK_KEY
REVENUECAT_TEST_STORE_PUBLIC_SDK_KEY
```

The Test Store key is already in the Git-ignored local build configuration. Flutter uses it only in debug builds on iOS or Android. The production SDK keys come from the two individual store configurations. Test Store prices and transactions are simulated. Supabase already has the sandbox environment and entitlement allowlist. End-to-end purchases in Flutter still require the RevenueCat server API key and successful Supabase verification.

Server-side Edge Function settings use the names in `backend/.env.example`: `REVENUECAT_API_KEY`, `REVENUECAT_WEBHOOK_AUTHORIZATION`, `REVENUECAT_WEBHOOK_SIGNING_SECRET`, `REVENUECAT_ENVIRONMENT` and `REVENUECAT_ENTITLEMENT_KEYS`. Enable HMAC signing on the RevenueCat integration and use the deployed `/functions/v1/revenuecat-webhook` endpoint. The server requires the configured Authorization header and the current provider's raw-body signature. A deployed endpoint with missing configuration is unavailable, not a working billing integration.

The mobile client shows actual store offering prices. It does not fabricate products or unlock paid state from local assertions. Purchase access also requires successful server verification.

## Optional cloud services

Provider keys remain server-side. Keep `AI_JOBS_ENABLED`, `IMPORT_JOBS_ENABLED`, `IMAGE_JOBS_ENABLED` and `MEDIA_UPLOADS_ENABLED` disabled until the relevant service, consent, retention, budget and end-to-end checks are ready. The backend README documents the exact variables and adapters.

Approve a specific model and spend cap before setting `OPENAI_API_KEY`/`COACH_MODEL`. Recipe URL import needs an operator-reviewed `IMPORT_ALLOWED_HOSTS` allowlist and egress protection; it is not an unrestricted internet fetcher. A user's photo attachment does not authorise uploading or analysing that photo. Verify private media upload, MIME/size/hash checks, metadata rejection, cancellation and deletion against the real hosted service.

## Content, operations and release

The catalogue contains **24 experimental recipe drafts**, **18 written technique drafts** and sourced guidance pending review. No kitchen validation, original technique film or licensed process-photo catalogue has been fabricated. Record actual trials, equipment/quantity limits, readiness cues, allergens, media rights and editorial approval before publishing them as reviewed content. Recovery branches and care envelopes require that evidence.

Owner inputs still needed include the legal/privacy controller, support/deletion contact, launch countries/languages/age policy, moderation/support ownership and operating capacity. Complete backup/restore, deletion/export, account sharing/revocation, provider failure and incident-response drills. Real phones, watches and named probes are required for lifecycle, permission, pairing and calibration acceptance.

Complete the remaining source work in the implementation ledger, get a full green verification run on the release candidate, perform the planned kitchen/accessibility/usability/device acceptance, and coordinate one full launch. The marketing changes are not yet published; they also need the verified privacy/deletion contact and final store links.
