# Crumb & Clock

A prelaunch marketing website for the sourdough mobile-app product plan. Original loaf-and-clock identity, editorial art direction, generated sourdough photography, four illustrative app screens, interactive feature tabs, and three substantive baking guides.

## Run

Requires Node.js 20.9+ (developed and tested on Node 24) and npm.

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

Set **`NEXT_PUBLIC_SITE_URL` to the real public origin before building** (e.g. `https://your-domain.com`, with no path). This determines canonical, sitemap, and structured-data URLs at build time. Without a public origin the local site has `noindex` and disallows crawling. Rebuild after changing the origin. Register the published sitemap with search engines after deployment. No indexing, ranking, name availability, trademark clearance, or reputation endorsements are claimed.

## Early access and privacy

The form is functional: `POST /api/waitlist` validates and deduplicates emails, records the requested platform and launch-update consent, and writes private JSONL records to `.data/waitlist.jsonl`. `/privacy` has a working removal form. Errors are shown to the visitor; a success message only appears after a successful write. No emails are sent and no third-party mailing-list service is connected.

This file store supports a **single Node process with a persistent writable disk**. Set `WAITLIST_DATA_DIR` to a private mounted persistent directory in production. It is unsuitable for ephemeral/serverless or multi-instance deployment; use a shared database or mailing-list adapter there. Do not commit records, expose their directory, or publish them as static assets. Before collecting public signups, configure storage/backups, the business's final privacy details and retention process, and any launch-email provider. For a real mailing campaign, add email ownership verification, verified unsubscribe links, and distributed anti-abuse controls. The current removal form intentionally gives the same response regardless of whether an address existed.

## Checks

```sh
npm run typecheck
npm run build
npm test
```

Playwright runs Chromium against the production server and can start it if port 3000 is free. The cloud machine has Chromium at `/usr/bin/chromium`. For other machines set `PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH`, or install Playwright's bundled browser with `npx playwright install chromium`. Tests exercise feature tabs and keyboard navigation, FAQs, signup persistence/deduplication/removal, input and origin rejection, article routes, social assets, mobile navigation, and horizontal overflow at five viewport widths. Test addresses are removed after a successful signup test. Accessibility audits cover the landing page, dialog, and an article.

## Brand and assets

- `public/brand/mark.svg`: original scalable loaf-and-clock mark.
- `public/brand/wordmark.svg`: standalone wordmark.
- `src/components/brand.tsx`: live website identity.
- `public/images/sourdough.webp`: generated editorial bread photography, not a user bake or testimonial.
- App screens are code-built **design previews**, not screenshots of a released app. Real screenshots can replace them when the app exists.
- Local DM Sans and DM Serif Display fonts are distributed by their Fontsource packages with their license files.
- `node scripts/generate-social-image.mjs` regenerates the sharing image (requires Sharp, supplied by Next.js).

## Before launch

Choose and clear the brand/domain, set the public origin and rebuild, configure durable signup storage and email delivery, finalise the privacy notice, then deploy. Pricing and app-store links should be added only when confirmed. App-store availability, testimonials, user counts, and released functionality have intentionally not been fabricated.
