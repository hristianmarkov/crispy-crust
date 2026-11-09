import type { MetadataRoute } from "next";
import { guides } from "@/data/guides";
import { siteUrl } from "@/lib/site";
export default function sitemap(): MetadataRoute.Sitemap {
  return [
    "",
    "/journal",
    "/privacy",
    ...guides.map((g) => `/journal/${g.slug}`),
  ].map((route) => ({
    url: `${siteUrl}${route}`,
    changeFrequency: route === "" ? "weekly" : "monthly",
    priority: route === "" ? 1 : route === "/privacy" ? 0.2 : 0.8,
  }));
}
