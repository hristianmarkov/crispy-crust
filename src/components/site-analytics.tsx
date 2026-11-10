"use client";

import { useEffect } from "react";
import { usePathname } from "next/navigation";
import { Analytics } from "@vercel/analytics/next";
import { allowsAnalytics, recordEvent } from "@/lib/analytics";

export function SiteAnalytics() {
  const path = usePathname();
  useEffect(() => {
    if (path.startsWith("/journal/") && !path.startsWith("/journal/topics/")) recordEvent("guide_view");
    let started = false;
    let completed = false;
    const start = (event: Event) => {
      if (started || !(event.target instanceof HTMLInputElement || event.target instanceof HTMLSelectElement)) return;
      if (!event.target.closest(".tools-calculator")) return;
      started = true;
      recordEvent("tool_started", { tool: path.startsWith("/tools/") ? path.split("/").pop() || "" : "embedded-rise" });
    };
    const complete = (event: Event) => {
      const detail = (event as CustomEvent<{ tool?: string }>).detail;
      if (!completed && detail?.tool && /^[a-z-]+$/.test(detail.tool)) {
        completed = true;
        recordEvent("tool_completed", { tool: detail.tool });
      }
    };
    const download = (event: MouseEvent) => {
      const link = (event.target as Element).closest?.("a");
      if (link?.pathname.startsWith("/downloads/")) recordEvent("printable_download", { file: link.pathname.split("/").pop() || "" });
    };
    document.addEventListener("input", start);
    document.addEventListener("change", start);
    document.addEventListener("click", download);
    window.addEventListener("crispy:tool-completed", complete);
    return () => {
      document.removeEventListener("input", start);
      document.removeEventListener("change", start);
      document.removeEventListener("click", download);
      window.removeEventListener("crispy:tool-completed", complete);
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
