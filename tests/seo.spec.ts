import { test, expect } from "@playwright/test";
import { guides } from "../src/data/guides";
import { journalTopics } from "../src/lib/journal";
import {
  calculateSchedule,
  defaultSchedule,
  isAvailable,
} from "../src/lib/schedule-calculator";

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

test("schedule arithmetic preserves cooling, midnight and conflicting hands-on work", () => {
  const alwaysHome = calculateSchedule({
    ...defaultSchedule,
    homeStart: "00:00",
    homeEnd: "00:00",
  });
  expect(alwaysHome.error).toBeNull();
  expect(alwaysHome.conflicts).toEqual([]);
  const cooling = alwaysHome.rows.find((row) => row.id === "cool")!;
  expect(cooling.end.getTime() - cooling.start.getTime()).toBe(
    defaultSchedule.cooling * 60_000,
  );
  expect(cooling.end.getTime()).toBe(alwaysHome.serving.getTime());
  expect(
    alwaysHome.rows.find((row) => row.id === "shape")!.start.getDate(),
  ).toBeLessThan(alwaysHome.serving.getDate());
  const overnightStart = new Date(2026, 10, 14, 23, 45);
  const overnightEnd = new Date(2026, 10, 15, 0, 10);
  expect(isAvailable(overnightStart, overnightEnd, "22:00", "02:00")).toBe(
    true,
  );
  expect(isAvailable(overnightStart, overnightEnd, "07:00", "22:00")).toBe(
    false,
  );
  const impossible = calculateSchedule({
    ...defaultSchedule,
    homeStart: "12:00",
    homeEnd: "12:01",
  });
  expect(impossible.conflicts.length).toBeGreaterThan(0);
  expect(impossible.laterServing).toBeNull();
  expect(impossible.rows.find((row) => row.id === "cool")!.end.getTime()).toBe(
    impossible.serving.getTime(),
  );
  expect(
    calculateSchedule({ ...defaultSchedule, mixing: defaultSchedule.bulk + 1 })
      .error,
  ).toBeTruthy();
});

test("feeding, hydration and rise calculators reconcile the playbook examples and reject invalid inputs", async ({
  page,
}) => {
  await page.goto("/tools/starter-feeding-calculator");
  await expect(
    page.getByRole("heading", { name: "Your feed by weight" }),
  ).toBeVisible();
  const feed = page.locator(".tools-stats");
  await expect(feed).toContainText("35 g");
  await expect(feed).toContainText("70 g");
  await expect(feed).toContainText("175 g");
  await page.getByLabel("Calculate from").selectOption("retained");
  await page.getByLabel("Retained starter (g)", { exact: true }).fill("20");
  await expect(feed).toContainText("100 g");
  await page.getByLabel("Fresh flour parts", { exact: true }).fill("0");
  await expect(
    page.getByText("Enter valid amounts in every field.", { exact: false }),
  ).toBeVisible();

  await page.goto("/tools/sourdough-hydration-calculator");
  await expect(
    page.getByRole("heading", { name: "72.7% total dough hydration" }),
  ).toBeVisible();
  await expect(page.locator(".tools-stats")).toContainText("550 g");
  await expect(page.locator(".tools-stats")).toContainText("400 g");
  await page.getByLabel("Starter hydration (%)", { exact: true }).fill("50");
  await expect(
    page.getByRole("heading", { name: "67.6% total dough hydration" }),
  ).toBeVisible();
  await page.getByLabel("Added flour (g)", { exact: true }).fill("");
  await expect(
    page.getByText("Enter valid amounts in every field.", { exact: false }),
  ).toBeVisible();
  await page
    .getByRole("button", { name: "Reset example", exact: true })
    .click();
  await expect(
    page.getByRole("heading", { name: "72.7% total dough hydration" }),
  ).toBeVisible();

  await page.goto("/tools/sourdough-rise-calculator");
  await expect(
    page.getByRole("heading", { name: "50% measured rise" }),
  ).toBeVisible();
  await page.getByLabel("Current reading (mL)", { exact: true }).fill("300");
  await expect(
    page.getByRole("heading", { name: "-25% measured rise" }),
  ).toBeVisible();
  await expect(
    page.getByText("The current reading is below the start.", { exact: false }),
  ).toBeVisible();
  await page.getByLabel("Starting reading (mL)", { exact: true }).fill("0");
  await expect(
    page.getByText("Enter valid amounts in every field.", { exact: false }),
  ).toBeVisible();
});

test("the schedule exposes a no-fit case and preserves the cooling stage in its downloadable plan", async ({
  page,
}) => {
  await page.goto("/tools/sourdough-schedule-calculator");
  await expect(page.getByRole("table")).toContainText("Cool before slicing");
  await page.getByLabel("Home each day from", { exact: true }).fill("12:00");
  await page.getByLabel("Home each day until", { exact: true }).fill("12:01");
  await expect(
    page.getByText("No fit was found in the next seven days", { exact: false }),
  ).toBeVisible();
  await expect(page.getByRole("table")).toContainText("Outside home window");
  const download = page.waitForEvent("download");
  await page
    .getByRole("button", { name: "Download schedule CSV", exact: true })
    .click();
  expect((await download).suggestedFilename()).toBe(
    "crispy-crust-sourdough-schedule.csv",
  );
});

test("the discard finder responds to grams and equipment rather than showing an unfiltered roundup", async ({
  page,
}) => {
  await page.goto("/tools/discard-recipe-finder");
  await expect(page.locator(".tools-recipe-card")).toHaveCount(5);
  await page
    .getByLabel("Usable discard on hand (g)", { exact: true })
    .fill("100");
  await expect(page.locator(".tools-recipe-card")).toHaveCount(1);
  await page.getByRole("combobox", { name: /equipment/i }).selectOption("Oven");
  await expect(page.locator(".tools-recipe-card")).toHaveCount(0);
  await expect(
    page.getByText("This collection starts at 100 g.", { exact: false }),
  ).toBeVisible();
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

test("journal search, direct worksheet links and the embedded rise tool form a working reader journey", async ({
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
  await expect(
    embedded.getByRole("heading", { name: "50% measured rise" }),
  ).toBeVisible();
  await embedded
    .getByLabel("Current reading (mL)", { exact: true })
    .fill("800");
  await expect(
    embedded.getByRole("heading", { name: "100% measured rise" }),
  ).toBeVisible();
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
