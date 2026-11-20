import { guides } from "@/data/guides";
import { tools } from "@/data/tools";
import { journalTopics } from "@/lib/journal";
import { siteUrl } from "@/lib/site";

export const dynamic = "force-static";

export function GET() {
  const text = [
    "# Crispy Crust",
    "",
    "> Crispy Crust is an upcoming sourdough baking app. The app is in development; no release date or pricing is announced. App screens are design previews. The free website tools and guides are available now.",
    "",
    "Guides contain attributed published methods and labelled illustrative examples. They do not claim original kitchen trials. Read source links, conditions and the editorial policy. Fermentation estimates support observation; they do not determine readiness.",
    "",
    "## About",
    `- [Home](${siteUrl}/): Upcoming mobile app, development status and static product previews.`,
    `- [Editorial policy](${siteUrl}/about): Attribution, examples and corrections.`,
    `- [Privacy](${siteUrl}/privacy): Data practices and email removal.`,
    "",
    "## Baking formulas and worked examples",
    ...tools.map((tool) => `- [${tool.title}](${siteUrl}/tools/${tool.slug}): ${tool.description}`),
    "",
    "## Topics",
    ...journalTopics.map((topic) => `- [${topic.name}](${siteUrl}/journal/topics/${topic.slug}): ${topic.description}`),
    "",
    "## Baking guides",
    ...guides.map((guide) => `- [${guide.title}](${siteUrl}/journal/${guide.slug}): ${guide.description}`),
    "",
  ].join("\n");
  return new Response(text, { headers: { "Content-Type": "text/plain; charset=utf-8" } });
}
