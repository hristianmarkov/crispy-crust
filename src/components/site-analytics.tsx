"use client";

import { useEffect } from "react";
import { usePathname } from "next/navigation";
import { Analytics } from "@vercel/analytics/next";
import { allowsAnalytics, recordEvent } from "@/lib/analytics";

export function SiteAnalytics() {
  const path = usePathname();
  useEffect(() => {
    if (path.startsWith("/journal/") && !path.startsWith("/journal/topics/")) recordEvent("guide_view");
    const download = (event: MouseEvent) => {
      const link = (event.target as Element).closest?.("a");
      if (link?.pathname.startsWith("/downloads/")) recordEvent("printable_download", { file: link.pathname.split("/").pop() || "" });
    };
    document.addEventListener("click", download);
    return () => {
      document.removeEventListener("click", download);
    };
  }, [path]);
  return <Analytics beforeSend={(event) => {
    if (!allowsAnalytics()) return null;
    const url = new URL(event.url);
    url.search = "";
    url.hash = "";
    return { ...event, url: url.toString() };
  }} />;
}
