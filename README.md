# Crispy Crust

A prelaunch marketing website for the sourdough mobile-app product plan. C-boule identity, editorial art direction, generated sourdough photography, four illustrative app screens, a recipe collection showcase and a static availability illustration, interactive feature tabs, and 53 substantive baking guides, seven topic hubs, five static formula/example pages and ungated printable worksheets.

## Run

Requires Node.js 22+ (developed and tested on Node 24) and npm.

```sh
npm ci
npm run dev
```

Production:

```sh
npm run build
npm start
```

Use the existing checkout in this isolated cloud environment; a separate worktree is unnecessary. The production server listens on port 3000 by default. `PORT=3001 npm start` changes the port. Verify readiness by requesting `/` and `/journal/sourdough-baking-schedule` and checking for the expected headings, not just an open port. Processes must be restarted in a fresh environment.

## SEO and answer discovery

Next.js App Router with statically generated landing, journal, article, and privacy pages; server-rendered product content; self-hosted fonts; local images; unique article metadata; canonical URLs; Open Graph and Twitter cards; sitemap and robots files; Organization, WebSite, FAQPage, Article and BreadcrumbList JSON-LD; short, direct answers and contextual internal links. `/llms.txt` provides a compact content map but is not a ranking guarantee. FAQ markup does not guarantee search-engine rich results.

Set **`NEXT_PUBLIC_SITE_URL` to the real public origin before building** (e.g. `https://www.crispycrust.app`, with no path). This determines canonical, sitemap, and structured-data URLs at build time. Development and Vercel Preview deployments are noindex and disallow crawling, independently of the configured canonical origin. The production fallback is the branded www origin. Rebuild after changing the origin. Register the published sitemap with search engines after deployment. Search indexing and ranking are not guaranteed.

## Marketing-only boundary and privacy

All baking functionality belongs to the Flutter app under `mobile/`. The public site contains product information, illustrative screen previews, static educational articles/formulas and printable downloads. Feature tabs, article search and navigation are content discovery controls; no recipe, schedule, journal or app account is created by the website.

The signup/removal forms and `/api/waitlist` route have been retired. The site no longer uses `SUPABASE_WAITLIST_URL` or `WAITLIST_SERVER_TOKEN`; it does not need database credentials to run. Historical Supabase waitlist records, rate-limit tables and the separately deployed Edge Function have **not** been changed or deleted by this implementation. Archived schema/configuration remains in `supabase/` as provenance, not an instruction to redeploy it. Do not turn historical signups into app accounts or treat them as consent to app analytics.

**Before deploying this privacy/retirement change:** the operator must publish a verified, monitored privacy/support contact, define historical-record retention and fulfil deletion requests. The draft notice accurately says it cannot accept/confirm individual requests yet. No unverified address or false claim that data was deleted is supplied. Disabling the historical Edge Function and rotating/removing its credentials is an owner-controlled retirement task; do not delete existing records automatically.

The CTA is an honest app-development status link; no store availability, release date, prices, waitlist confirmation or download links are fabricated. The old `/tools/` URLs remain as static worked examples and `WebPage` structured data, preserving existing guide links without a functional web app.

## Checks

```sh
npm run typecheck
npm run build
npm test
```

Playwright runs Chromium against the production server and can start it if port 3000 is free. The cloud machine has Chromium at `/usr/bin/chromium`. For other machines set `PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH`, or install Playwright's bundled browser with `npx playwright install chromium`. Tests exercise feature tabs and keyboard navigation, FAQs, absence of signup forms/API, static development-status messaging, article routes, social assets, mobile navigation, and horizontal overflow at five viewport widths. Accessibility audits cover the landing page, static formula pages, and articles.

## Brand and assets

- `public/brand/mark.svg`: approved scalable C-boule mark from the mobile handoff.
- `public/brand/wordmark.svg`: outlined DM Serif Display wordmark from the mobile handoff.
- `src/components/brand.tsx`: live website identity.
- `public/images/sourdough.webp`: generated editorial bread photography, not a user bake or testimonial.
- App screens are code-built **design previews**, not screenshots of a released app. Real screenshots can replace them when the app exists.
- Local DM Sans and DM Serif Display fonts are distributed by their Fontsource packages with their license files.
- `node scripts/generate-social-image.mjs` regenerates the sharing image (requires Sharp, supplied by Next.js).

## Before launch

The branded domain is configured; signup functionality has been retired. Owner verification in Search Console and Bing Webmaster Tools, search-engine sitemap submission, analytics dashboard activation, and original baking fieldwork require their respective access or evidence. See docs/seo-implementation.md for the implementation record. Pricing and app-store links should be added only when confirmed. App-store availability, testimonials, user counts, and released functionality have intentionally not been fabricated.

## SEO content and publishing

The 50 supplied drafts are stored in `src/data/imported-guides.json`, alongside the three preserved guides in `src/data/guides.ts`. The journal renders body tables, lists, stable section anchors, sources and curated internal links in HTML. `scripts/import-guides.py` can regenerate imported content from the supplied DOCX when its source path is provided. Dates describe the actual page publication or meaningful edit, not expert review.

The app remains upcoming. Recipe adaptations are attributed and visibly identified as not independently bake-tested by Crispy Crust; original trial photos and expert review are not fabricated. Recipe rich-result markup is withheld until the corresponding testing and representative image evidence exists. Generated article sharing cards are typography cards, not images of tested bakes.

Worksheets under `public/downloads/` include A4, US Letter and HTML variants. Regenerate with `python scripts/generate-printables.py` (requires ReportLab). No email gate is used.

`GOOGLE_SITE_VERIFICATION` and `BING_SITE_VERIFICATION` accept the exact owner codes from the respective webmaster consoles; rebuild after setting them. Verify a Domain property for `crispycrust.app`, submit `https://www.crispycrust.app/sitemap.xml`, and inspect the declared and selected canonicals after recrawl.

Vercel Web Analytics integration records pageviews and `guide_view` and `printable_download`. Only event names, page paths and controlled tool/file identifiers are sent. Query strings, email addresses and baking entries are excluded; Do Not Track and Global Privacy Control are respected. Enable Web Analytics for the existing Vercel project before treating collection as operational; custom-event availability depends on the current account plan.

An IndexNow ownership key is public under `public/` and recorded in `scripts/indexnow-key.txt`. `node scripts/submit-indexnow.mjs` submits the canonical sitemap URLs to IndexNow. On a push to main, the GitHub workflow waits until the public release marker matches that exact commit before submitting, and can also be run manually. A successful submission means acceptance of the request, not guaranteed indexing.
