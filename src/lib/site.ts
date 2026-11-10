export const siteUrl = new URL(
  process.env.NEXT_PUBLIC_SITE_URL || "https://www.crispycrust.app",
).origin;
// A production origin in a preview build must never make that preview indexable.
export const isPublicSite = process.env.VERCEL_ENV
  ? process.env.VERCEL_ENV === "production"
  : process.env.NODE_ENV === "production";
