# Crispy Crust

A prelaunch marketing website for the sourdough mobile-app product plan. Original loaf-and-clock identity, editorial art direction, generated sourdough photography, four illustrative app screens, a recipe collection showcase and interactive availability examples, interactive feature tabs, and 53 substantive baking guides, seven topic hubs, five free web tools and ungated printable worksheets.

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

## Early access and privacy

The form sends validated requests through the Next.js server to the authenticated `crumb-clock-waitlist` Supabase Edge Function. The function uses Supabase's built-in service credentials to call a restricted database function. No database credentials reach the browser. Email addresses are deduplicated by a unique constraint. Removal returns the same success response whether a record existed or not.

`public.crumb_clock_waitlist` has RLS enabled and no access for `anon` or `authenticated`. Only the service role can read or modify the records. Database rate limits allow eight requests per minute per daily keyed IP hash; raw IPs are not stored. Expired rate entries are cleaned on subsequent requests. No email is sent by signup.

Production settings: Next.js preset, Node 24, default output directory, `NEXT_PUBLIC_SITE_URL=https://www.crispycrust.app`. Server-only variables are `SUPABASE_WAITLIST_URL` and `WAITLIST_SERVER_TOKEN`. The Edge Function checks the SHA-256 digest of that token before accessing the database. To rotate it, generate a new random token, replace its digest in the function, redeploy the function, update the Vercel secret and redeploy the website. Never commit the raw token.

The applied database schema is recorded in `supabase/schema/waitlist.sql`; Supabase migration history tracks its deployment. Deploy the function using `supabase/config.toml` (custom token authentication). Do not expose service-role credentials. Development/preview deployments require their own backend configuration; without it the form fails explicitly rather than claiming success.

## Checks

```sh
npm run typecheck
npm run build
npm test
```

Playwright runs Chromium against the production server and can start it if port 3000 is free. The cloud machine has Chromium at `/usr/bin/chromium`. For other machines set `PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH`, or install Playwright's bundled browser with `npx playwright install chromium`. Tests exercise feature tabs and keyboard navigation, FAQs, signup confirmation/deduplication/removal, input and origin rejection, article routes, social assets, mobile navigation, and horizontal overflow at five viewport widths. Test addresses are removed after a successful signup test. Accessibility audits cover the landing page, dialog, and an article.

## Brand and assets

- `public/brand/mark.svg`: original scalable loaf-and-clock mark.
- `public/brand/wordmark.svg`: standalone wordmark.
- `src/components/brand.tsx`: live website identity.
- `public/images/sourdough.webp`: generated editorial bread photography, not a user bake or testimonial.
- App screens are code-built **design previews**, not screenshots of a released app. Real screenshots can replace them when the app exists.
- Local DM Sans and DM Serif Display fonts are distributed by their Fontsource packages with their license files.
- `node scripts/generate-social-image.mjs` regenerates the sharing image (requires Sharp, supplied by Next.js).

## Before launch

The branded domain and durable signup storage are configured. Owner verification in Search Console and Bing Webmaster Tools, search-engine sitemap submission, analytics dashboard activation, and original baking fieldwork require their respective access or evidence. See docs/seo-implementation.md for the implementation record. Pricing and app-store links should be added only when confirmed. App-store availability, testimonials, user counts, and released functionality have intentionally not been fabricated.

## SEO content and publishing

The 50 supplied drafts are stored in `src/data/imported-guides.json`, alongside the three preserved guides in `src/data/guides.ts`. The journal renders body tables, lists, stable section anchors, sources and curated internal links in HTML. `scripts/import-guides.py` can regenerate imported content from the supplied DOCX when its source path is provided. Dates describe the actual page publication or meaningful edit, not expert review.

The app remains upcoming. Recipe adaptations are attributed and visibly identified as not independently bake-tested by Crispy Crust; original trial photos and expert review are not fabricated. Recipe rich-result markup is withheld until the corresponding testing and representative image evidence exists. Generated article sharing cards are typography cards, not images of tested bakes.

Worksheets under `public/downloads/` include A4, US Letter and HTML variants. Regenerate with `python scripts/generate-printables.py` (requires ReportLab). No email gate is used.

`GOOGLE_SITE_VERIFICATION` and `BING_SITE_VERIFICATION` accept the exact owner codes from the respective webmaster consoles; rebuild after setting them. Verify a Domain property for `crispycrust.app`, submit `https://www.crispycrust.app/sitemap.xml`, and inspect the declared and selected canonicals after recrawl.

Vercel Web Analytics integration records pageviews and `guide_view`, `tool_started`, `tool_completed`, `printable_download`, `waitlist_open` and `waitlist_signup_success`. Only event names, page paths and controlled tool/file identifiers are sent. Query strings, email addresses and calculator values are excluded; Do Not Track and Global Privacy Control are respected. Enable Web Analytics for the existing Vercel project before treating collection as operational; custom-event availability depends on the current account plan.

An IndexNow ownership key is public under `public/` and recorded in `scripts/indexnow-key.txt`. `node scripts/submit-indexnow.mjs` submits the canonical sitemap URLs to IndexNow. The GitHub workflow runs this only after successful production deployment notifications and can also be run manually. A successful submission means acceptance of the request, not guaranteed indexing.
