import { test, expect } from "@playwright/test";
import { readFile } from "node:fs/promises";
import path from "node:path";

test("home has server-rendered product information and structured answers", async ({
  page,
  request,
}) => {
  const response = await request.get("/");
  const html = await response.text();
  expect(html).toContain("application/ld+json");
  expect(html).toContain("FAQPage");
  expect(html).toContain("Get to know");
  expect(html).toContain("Keep the");
  await page.goto("/");
  await expect(page.getByRole("heading", { level: 1 })).toHaveText(
    "Good bread.On your time.",
  );
  const errors: string[] = [];
  page.on("pageerror", (e) => errors.push(e.message));
  for (const label of [
    "A happier starter",
    "Plans with breathing room",
    "Your best loaf, again",
    "A little daily clarity",
  ]) {
    await page.getByRole("tab", { name: label }).click();
    await expect(page.getByRole("tab", { name: label })).toHaveAttribute(
      "aria-selected",
      "true",
    );
    await expect(page.getByRole("tabpanel")).toBeVisible();
  }
  await page.getByRole("tab", { name: "A little daily clarity" }).focus();
  await page.keyboard.press("ArrowRight");
  await expect(
    page.getByRole("tab", { name: "A happier starter" }),
  ).toBeFocused();
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

test("signup persists once, provides a confirmation and can be removed", async ({
  page,
  request,
}) => {
  const email = `browser-${Date.now()}@example.com`;
  await page.goto("/");
  await page
    .getByRole("button", { name: "Join the early birds" })
    .first()
    .click();
  const dialog = page.getByRole("dialog", {
    name: "First in line. Fresh from the oven.",
  });
  await expect(dialog).toBeVisible();
  await page.getByLabel("Your email address").fill(email);
  await page.getByLabel("What’s in your pocket?").selectOption("android");
  await page.getByRole("button", { name: "Save me a little spot" }).click();
  await expect(
    page.getByRole("heading", { name: "You’re on the list." }),
  ).toBeVisible();
  const file = path.join(process.cwd(), ".data/waitlist.jsonl");
  const content = await readFile(file, "utf8");
  expect(content).toContain(email);
  const duplicate = await request.post("/api/waitlist", {
    data: { email, platform: "android" },
  });
  expect(duplicate.ok()).toBeTruthy();
  const lines = (await readFile(file, "utf8"))
    .split("\n")
    .filter((l) => l.includes(email));
  expect(lines).toHaveLength(1);
  await page.getByRole("button", { name: "Back to the good stuff" }).click();
  await expect(page.getByRole("dialog")).not.toBeVisible();
  await page.goto("/privacy");
  await page.getByLabel("Email address to remove").fill(email);
  await page.getByRole("button", { name: "Remove my email" }).click();
  await expect(page.getByRole("status")).toContainText(
    "its record has been removed",
  );
  expect(await readFile(file, "utf8")).not.toContain(email);
});

test("invalid signup and cross-origin writes are rejected", async ({
  request,
}) => {
  const invalid = await request.post("/api/waitlist", {
    data: { email: "not-an-email", platform: "ios" },
  });
  expect(invalid.status()).toBe(400);
  const foreign = await request.post("/api/waitlist", {
    headers: { Origin: "https://unrelated.example" },
    data: { email: "test@example.com", platform: "ios" },
  });
  expect(foreign.status()).toBe(403);
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

test("mobile navigation, modal and layouts work without horizontal overflow", async ({
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
  await page.setViewportSize({ width: 390, height: 844 });
  await page
    .getByRole("button", { name: "Join the early birds" })
    .last()
    .click();
  await expect(page.getByRole("dialog")).toBeVisible();
  await page.keyboard.press("Escape");
  await expect(page.getByRole("dialog")).not.toBeVisible();
});

test("landing page, signup dialog and guide pass automated accessibility checks", async ({
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
  await page
    .getByRole("button", { name: "Join the early birds" })
    .first()
    .click();
  result = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21aa"])
    .analyze();
  expect(
    result.violations.map((v) => ({
      id: v.id,
      targets: v.nodes.map((n) => n.target),
    })),
  ).toEqual([]);
  await page.keyboard.press("Escape");
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
