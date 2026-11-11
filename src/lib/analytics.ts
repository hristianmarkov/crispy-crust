"use client";

import { track } from "@vercel/analytics";

export function allowsAnalytics() {
  return typeof window !== "undefined" && navigator.doNotTrack !== "1" &&
    !(navigator as Navigator & { globalPrivacyControl?: boolean }).globalPrivacyControl;
}

export function recordEvent(name: "guide_view" | "tool_started" | "tool_completed" | "printable_download", properties: Record<string, string> = {}) {
  if (!allowsAnalytics()) return;
  // Only controlled event names, paths and tool identifiers; never form values.
  const data = { path: window.location.pathname, ...properties };
  window.dispatchEvent(new CustomEvent("crispy:analytics", { detail: { name, data } }));
  if (process.env.NODE_ENV === "production") track(name, data);
}
