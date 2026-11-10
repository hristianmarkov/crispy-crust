import type { MetadataRoute } from "next";
import { guides } from "@/data/guides";
import { siteUrl } from "@/lib/site";
import { journalTopics } from "@/lib/journal";
import { tools } from "@/data/tools";
export default function sitemap(): MetadataRoute.Sitemap {
  return [
    "/",
    "/journal",
    "/privacy",
    "/about",
    "/tools",
    ...tools.map((tool) => `/tools/${tool.slug}`),
    ...journalTopics.map((topic) => `/journal/topics/${topic.slug}`),
    ...guides.map((g) => `/journal/${g.slug}`),
  ].map((route) => ({
    url: `${siteUrl}${route}`,
    ...(guides.find((guide) => route === `/journal/${guide.slug}`)?.updatedAt
      ? { lastModified: guides.find((guide) => route === `/journal/${guide.slug}`)!.updatedAt }
      : {}),
  }));
}
