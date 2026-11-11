import { test, expect } from "@playwright/test";
import { guides } from "../src/data/guides";
import { journalTopics } from "../src/lib/journal";

const origin = "https://www.crispycrust.app";
const tools = [
  "/tools",
  "/tools/starter-feeding-calculator",
  "/tools/sourdough-schedule-calculator",
  "/tools/sourdough-hydration-calculator",
  "/tools/sourdough-rise-calculator",
  "/tools/discard-recipe-finder",
];

function attribute(
  html: string,
  name: string,
  value: string,
  result = "content",
) {
  for (const tag of html.match(/<(?:meta|link)\b[^>]*>/g) ?? []) {
    if (tag.includes(`${name}="${value}"`)) {
      return tag
        .match(new RegExp(`${result}="([^"]+)"`))?.[1]
        ?.replaceAll("&amp;", "&");
    }
  }
  return undefined;
}
function schemaGraph(html: string): Record<string, unknown>[] {
  return [
    ...html.matchAll(
      /<script\b[^>]*type="application\/ld\+json"[^>]*>([\s\S]*?)<\/script>/g,
    ),
  ].flatMap((match) => {
    const value = JSON.parse(match[1]);
    return value["@graph"] ?? [value];
  });
}

test("the complete library has canonical server-rendered answers and consistent article entities", async ({
  request,
}) => {
  test.setTimeout(90_000);
  expect(guides).toHaveLength(53);
  expect(new Set(guides.map((guide) => guide.slug)).size).toBe(53);
  const titles = new Set<string>();
  const descriptions = new Set<string>();
  const images = new Set<string>();
  for (const guide of guides) {
    const route = `/journal/${guide.slug}`;
    const response = await request.get(route);
    expect(response.status(), route).toBe(200);
    const html = await response.text();
    expect(attribute(html, "rel", "canonical", "href"), route).toBe(
      `${origin}${route}`,
    );
    expect(attribute(html, "property", "og:url"), route).toBe(
      `${origin}${route}`,
    );
    expect(attribute(html, "property", "og:type"), route).toBe("article");
    const description = attribute(html, "name", "description");
    const title = html.match(/<title>([^<]+)<\/title>/)?.[1];
    const image = attribute(html, "property", "og:image");
    expect(title, route).toBeTruthy();
    expect(description, route).toBeTruthy();
    expect(image, route).toContain(guide.slug);
    expect(attribute(html, "name", "twitter:title"), route).toBeTruthy();
    titles.add(title!);
    descriptions.add(description!);
    images.add(image!);
    expect(html, route).toContain("article-intro");
    expect(html, route).toContain('aria-label="In this guide"');
    const graph = schemaGraph(html);
    const article = graph.find((item) => item["@type"] === "Article");
    expect(article, route).toBeTruthy();
    const mainEntity = article!.mainEntityOfPage;
    expect(
      typeof mainEntity === "string"
        ? mainEntity
        : (mainEntity as Record<string, unknown>)["@id"],
      route,
    ).toBe(`${origin}${route}`);
    expect(article!.datePublished, route).toMatch(/^\d{4}-\d{2}-\d{2}/);
    expect(article!.dateModified, route).toMatch(/^\d{4}-\d{2}-\d{2}/);
    const breadcrumbs = graph.find(
      (item) => item["@type"] === "BreadcrumbList",
    );
    expect(breadcrumbs, route).toBeTruthy();
    const crumbs = breadcrumbs!.itemListElement as { item: string }[];
    for (const crumb of crumbs)
      expect(crumb.item, route).toMatch(
        /^https:\/\/www\.crispycrust\.app(?:\/|$)/,
      );
    expect(crumbs.at(-1)?.item, route).toBe(`${origin}${route}`);
    expect(JSON.stringify(graph), route).not.toContain(
      "crispy-crust.vercel.app",
    );
  }
  expect(titles.size).toBe(53);
  expect(descriptions.size).toBe(53);
  expect(images.size).toBe(53);
});

test("the sitemap, robots and content hubs expose only canonical public destinations", async ({
  request,
}) => {
  const sitemap = await request.get("/sitemap.xml");
  expect(sitemap.status()).toBe(200);
  const xml = await sitemap.text();
  const urls = [...xml.matchAll(/<loc>([^<]+)<\/loc>/g)].map(
    (match) => match[1],
  );
  expect(new Set(urls).size).toBe(urls.length);
  for (const url of urls)
    expect(url).toMatch(/^https:\/\/www\.crispycrust\.app(?:\/|$)/);
  for (const route of [
    "/",
    "/journal",
    "/about",
    "/privacy",
    ...tools,
    ...guides.map((guide) => `/journal/${guide.slug}`),
    ...journalTopics.map((topic) => `/journal/topics/${topic.slug}`),
  ]) {
    expect(urls, route).toContain(`${origin}${route}`);
  }
  const robots = await (await request.get("/robots.txt")).text();
  expect(robots).toContain(`Sitemap: ${origin}/sitemap.xml`);
  expect(robots).toContain("Allow: /");
  expect(robots).not.toContain("crispy-crust.vercel.app");
  const journal = await (await request.get("/journal")).text();
  for (const guide of guides)
    expect(journal, guide.slug).toContain(`href="/journal/${guide.slug}"`);
  for (const route of [
    ...tools,
    "/about",
    ...journalTopics.map((topic) => `/journal/topics/${topic.slug}`),
  ]) {
    const response = await request.get(route);
    expect(response.status(), route).toBe(200);
    const html = await response.text();
    expect(attribute(html, "rel", "canonical", "href"), route).toBe(
      `${origin}${route}`,
    );
    expect(html, route).toContain("<h1");
  }
});

test("the old hostname preserves nested paths and queries in a permanent redirect", async ({
  request,
}) => {
  for (const path of [
    "/?utm_source=legacy",
    "/journal/sourdough-baking-schedule?utm_source=legacy&ref=guide",
  ]) {
    const response = await request.get(path, {
      headers: { Host: "crispy-crust.vercel.app" },
      maxRedirects: 0,
    });
    expect([301, 308], path).toContain(response.status());
    expect(new URL(response.headers().location).href, path).toBe(
      new URL(`${origin}${path}`).href,
    );
  }
});

test("unknown guides and topics return a real 404", async ({ request }) => {
  for (const route of [
    "/journal/not-a-guide",
    "/journal/topics/not-a-topic",
    "/this-page-does-not-exist",
  ]) {
    expect((await request.get(route)).status(), route).toBe(404);
  }
});

test("former tools are static explainers, not web application calculators", async ({ page }) => {
  for (const route of tools.slice(1)) {
    await page.goto(route);
    await expect(page.locator("main")).toContainText("Worked example only.");
    await expect(page.locator("main input, main select, main textarea, main form")).toHaveCount(0);
    await expect(page.getByRole("heading", { name: "Worked example", exact: true })).toBeVisible();
    const html = await page.content();
    expect(html).not.toContain('"@type":"WebApplication"');
  }
});

test("A4 and Letter printables download as PDFs without a signup gate", async ({
  request,
}) => {
  for (const name of [
    "starter-feeding-log",
    "sourdough-bake-journal",
    "weekend-sourdough-schedule",
    "sourdough-formula-card",
    "bulk-fermentation-chart",
  ]) {
    for (const size of ["a4", "letter"]) {
      const route = `/downloads/${name}-${size}.pdf`;
      const response = await request.get(route);
      expect(response.status(), route).toBe(200);
      expect(response.headers()["content-type"], route).toContain(
        "application/pdf",
      );
      expect((await response.body()).subarray(0, 5).toString(), route).toBe(
        "%PDF-",
      );
    }
  }
});

test("journal and tools remain usable on a narrow mobile screen", async ({
  page,
}) => {
  await page.setViewportSize({ width: 390, height: 844 });
  for (const route of [
    "/journal",
    "/journal/bulk-fermentation-chart",
    "/tools/starter-feeding-calculator",
    "/tools/sourdough-schedule-calculator",
    "/tools/sourdough-hydration-calculator",
  ]) {
    await page.goto(route);
    await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= window.innerWidth,
      ),
      route,
    ).toBe(true);
  }
  const { default: AxeBuilder } = await import("@axe-core/playwright");
  for (const route of [
    "/journal",
    "/journal/bulk-fermentation-chart",
    "/tools/sourdough-hydration-calculator",
  ]) {
    await page.goto(route);
    const result = await new AxeBuilder({ page })
      .withTags(["wcag2a", "wcag2aa", "wcag21aa"])
      .analyze();
    expect(
      result.violations.map((violation) => ({
        id: violation.id,
        targets: violation.nodes.map((node) => node.target),
      })),
      route,
    ).toEqual([]);
  }
});

test("journal search, direct worksheet links and static rise guidance form a reader journey", async ({
  page,
}) => {
  await page.goto("/journal");
  await page
    .getByLabel("Search the journal", { exact: true })
    .fill("no-such-sourdough-topic-123");
  await expect(
    page.getByRole("heading", { name: "No guides for that search yet." }),
  ).toBeVisible();
  await page
    .getByRole("button", { name: "Show all guides", exact: true })
    .click();
  await expect(page.locator(".library-guide")).toHaveCount(53);
  const log = guides.find((guide) => guide.number === 9)!;
  await page.goto(`/journal/${log.slug}`);
  await expect(
    page.getByRole("link", {
      name: "Starter feeding log — A4 PDF",
      exact: true,
    }),
  ).toHaveAttribute("href", "/downloads/starter-feeding-log-a4.pdf");
  await expect(
    page.getByRole("link", {
      name: "Starter feeding log — US Letter PDF",
      exact: true,
    }),
  ).toHaveAttribute("href", "/downloads/starter-feeding-log-letter.pdf");
  expect(await page.locator("article").innerText()).not.toMatch(
    /\]\]\(https?:/,
  );
  const rise = guides.find((guide) => guide.number === 16)!;
  await page.goto(`/journal/${rise.slug}`);
  const embedded = page.locator(".embedded-rise-calculator");
  await expect(embedded).toContainText("400 mL starting mark rising to 600 mL is a 50% increase");
  await expect(embedded.locator("input,select,button")).toHaveCount(0);

});

test("server-rendered navigation and contextual internal links lead to live destinations", async ({
  request,
}) => {
  test.setTimeout(90_000);
  const links = new Set<string>();
  for (const route of [
    "/",
    "/journal",
    "/about",
    ...tools,
    ...journalTopics.map((topic) => `/journal/topics/${topic.slug}`),
    ...guides.map((guide) => `/journal/${guide.slug}`),
  ]) {
    const html = await (await request.get(route)).text();
    for (const match of html.matchAll(/href="(\/(?!\/)[^"]*)"/g)) {
      const href = match[1].replaceAll("&amp;", "&");
      if (/^\/(?:_next|api)(?:\/|$)/.test(href)) continue;
      const url = new URL(href, origin);
      links.add(`${url.pathname}${url.search}`);
    }
  }
  for (const link of links)
    expect((await request.get(link)).status(), link).toBe(200);
});
