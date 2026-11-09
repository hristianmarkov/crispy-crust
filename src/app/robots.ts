import type { MetadataRoute } from "next";
import { isPublicSite, siteUrl } from "@/lib/site";
export default function robots(): MetadataRoute.Robots {
  return {
    rules: isPublicSite
      ? { userAgent: "*", allow: "/", disallow: "/api/" }
      : { userAgent: "*", disallow: "/" },
    ...(isPublicSite ? { sitemap: `${siteUrl}/sitemap.xml` } : {}),
  };
}
