import { guides, type Guide } from "@/data/guides";

export const journalTopics = [
  { slug: "starter-care", name: "Starter care", description: "Feed, observe and care for your culture. Start with the jar in front of you, then build a routine you can repeat.", tool: "/tools/starter-feeding-calculator", toolName: "Work out your next feed" },
  { slug: "fermentation", name: "Fermentation", description: "Follow dough temperature, rise and texture through bulk and final proof. Learn what each measurement can tell you — and where its limits are.", tool: "/tools/sourdough-rise-calculator", toolName: "Calculate a rise target" },
  { slug: "troubleshooting", name: "Troubleshooting", description: "Turn a sticky crumb, spreading dough or pale crust into a useful next observation. Compare the possible causes before changing your next bake.", tool: "/tools/sourdough-hydration-calculator", toolName: "Check your dough hydration" },
  { slug: "scheduling", name: "Scheduling", description: "Work backwards from the bread you want to serve, with space for work, sleep, cooling and a dough that changes pace.", tool: "/tools/sourdough-schedule-calculator", toolName: "Plan a bake around your day" },
  { slug: "recipes-techniques", name: "Recipes & techniques", description: "Understand the ingredients and handling behind a loaf, from folding and shaping to scoring and baking. Recipe adaptations include their published sources.", tool: "/tools/sourdough-hydration-calculator", toolName: "Understand the formula" },
  { slug: "tools-logging", name: "Tools & logging", description: "Keep the useful numbers: flour, water, starter, temperature and what actually happened. Find the maths and worksheets to make your next bake easier to compare.", tool: "/tools", toolName: "Open the baker’s tools" },
  { slug: "discard", name: "Discard", description: "Understand what discard does in a recipe, how to handle it, and which published recipe fits the amount in your jar.", tool: "/tools/discard-recipe-finder", toolName: "Find a recipe by grams available" },
] as const;

export function topicForGuide(guide: Guide) {
  if (guide.category) return journalTopics.find((topic) => topic.name === guide.category);
  if (guide.slug === "sourdough-baking-schedule") return journalTopics[3];
  if (guide.slug === "when-is-sourdough-starter-ready") return journalTopics[0];
  return journalTopics[1];
}

export function relatedGuides(guide: Guide) {
  const specified = (guide.relatedSlugs ?? [])
    .map((slug) => guides.find((item) => item.slug === slug))
    .filter((item): item is Guide => Boolean(item) && item?.slug !== guide.slug);
  const sameTopic = guides.filter((item) => item.slug !== guide.slug && topicForGuide(item)?.slug === topicForGuide(guide)?.slug);
  return [...new Map([...specified, ...sameTopic].map((item) => [item.slug, item])).values()].slice(0, 3);
}

export function sectionId(text: string) {
  return text.toLowerCase().replace(/[’']/g, "").replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
}
