import { test, expect } from "@playwright/test";

test("home has server-rendered product information and structured answers", async ({
  page,
  request,
}) => {
  const response = await request.get("/");
  const html = await response.text();
  expect(html).toContain("application/ld+json");
  expect(html).toContain("FAQPage");
  expect(html).toContain("recipe-specific");
  expect(html).toContain("Cold proof");
  await page.goto("/");
  await expect(page.getByRole("heading", { level: 1 })).toHaveText(
    "Good bread.On your time.",
  );
  const errors: string[] = [];
  page.on("pageerror", (e) => errors.push(e.message));
  for (const label of [
    "Starter care",
    "Your schedule",
    "Bake journal",
    "Guided bake",
  ]) {
    await page.getByRole("tab", { name: label }).click();
    await expect(page.getByRole("tab", { name: label })).toHaveAttribute(
      "aria-selected",
      "true",
    );
    await expect(page.getByRole("tabpanel")).toBeVisible();
  }
  await page.getByRole("tab", { name: "Guided bake" }).focus();
  await page.keyboard.press("ArrowRight");
  await expect(page.getByRole("tab", { name: "Starter care" })).toBeFocused();
  await page
    .getByRole("button", {
      name: "When can I download it? Will it be on iOS and Android?",
    })
    .click();
  await expect(
    page.getByText("The app is in development, and a release date"),
  ).toBeVisible();
  expect(errors).toEqual([]);
});

test("marketing CTAs disclose development status and do not collect signups", async ({ page, request }) => {
  await page.goto("/");
  await page.locator(".hero-actions").getByRole("link", { name: "App in development" }).click();
  await expect(page.locator("#app-status")).toBeInViewport();
  await expect(page.locator("#app-status")).toContainText("Not publicly released yet");
  await expect(page.locator("form")).toHaveCount(0);
  await expect(page.getByRole("dialog")).toHaveCount(0);
  await expect(page.locator('a[href*="apps.apple.com"], a[href*="play.google.com"]')).toHaveCount(0);
  expect((await request.post("/api/waitlist", { data: { email: "not-collected@example.com" } })).status()).toBe(404);
  await page.goto("/privacy");
  await expect(page.locator("main")).toContainText("does not itself delete previously collected records");
  await expect(page.locator("form")).toHaveCount(0);
});

test("guides, sitemap, robots and social image are available", async ({
  page,
  request,
}) => {
  await page.goto("/journal");
  await page
    .getByRole("link", { name: /How to plan sourdough around your day/ })
    .click();
  await expect(page.getByRole("heading", { level: 1 })).toHaveText(
    "How to plan sourdough around your day",
  );
  await expect(
    page.getByRole("navigation", { name: "In this guide" }),
  ).toBeVisible();
  for (const route of [
    "/journal/when-is-sourdough-starter-ready",
    "/journal/when-is-bulk-fermentation-done",
    "/privacy",
    "/sitemap.xml",
    "/robots.txt",
    "/images/social-card.jpg",
  ]) {
    const res = await request.get(route);
    expect(res.status(), route).toBe(200);
  }
  await page.goto("/journal/this-does-not-exist");
  await expect(
    page.getByRole("heading", { name: "A little off the recipe." }),
  ).toBeVisible();
});

test("mobile navigation and layouts work without horizontal overflow", async ({
  page,
}) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto("/");
  await expect(
    page.getByRole("button", { name: "Open navigation" }),
  ).toBeVisible();
  await page.getByRole("button", { name: "Open navigation" }).click();
  await page
    .getByRole("link", { name: "The good stuff", exact: true })
    .first()
    .click();
  await expect(
    page.getByRole("button", { name: "Open navigation" }),
  ).toBeVisible();
  for (const width of [360, 390, 768, 1280, 1440]) {
    await page.setViewportSize({ width, height: 900 });
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= window.innerWidth,
      ),
      `overflow at ${width}`,
    ).toBeTruthy();
  }

});

test("landing page and guide pass automated accessibility checks", async ({
  page,
}) => {
  const { default: AxeBuilder } = await import("@axe-core/playwright");
  await page.goto("/");
  let result = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21aa"])
    .analyze();
  expect(
    result.violations.map((v) => ({
      id: v.id,
      targets: v.nodes.map((n) => n.target),
    })),
  ).toEqual([]);
  await page.goto("/journal/sourdough-baking-schedule");
  result = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21aa"])
    .analyze();
  expect(
    result.violations.map((v) => ({
      id: v.id,
      targets: v.nodes.map((n) => n.target),
    })),
  ).toEqual([]);
});

test("recipe choices and practical scheduling examples explain the product", async ({
  page,
}) => {
  await page.goto("/");
  await expect(
    page.getByRole("heading", { name: "Rosemary focaccia" }),
  ).toBeVisible();
  await expect(page.locator(".schedule-demo")).toContainText("Static illustration — not a working planner");
  await expect(page.locator(".schedule-demo button, .schedule-demo input, .schedule-demo select")).toHaveCount(0);
  for (const width of [360, 768, 1440]) {
    await page.setViewportSize({ width, height: 900 });
    const device = await page.locator(".hero-phone").evaluate((el) => {
      const screen = el.querySelector(".phone-screen") as HTMLElement;
      return {
        ratio:
          (el as HTMLElement).offsetHeight / (el as HTMLElement).offsetWidth,
        clipped: screen.scrollHeight > screen.clientHeight,
      };
    });
    expect(device.ratio).toBeLessThan(2.1);
    expect(device.ratio).toBeGreaterThan(1.9);
    expect(device.clipped).toBe(false);
  }
});
