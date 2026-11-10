import { ImageResponse } from "next/og";
import { guides } from "@/data/guides";
import { topicForGuide } from "@/lib/journal";

export const size = { width: 1200, height: 630 };
export const contentType = "image/png";
export const alt = "Sourdough guidance from the Crispy Crust Baker’s Journal";

export default async function Image({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const guide = guides.find((item) => item.slug === slug);
  return new ImageResponse(<div style={{ width: "100%", height: "100%", background: "#f8f7f0", color: "#30352a", display: "flex", flexDirection: "column", padding: "64px 76px", justifyContent: "space-between", borderTop: "14px solid #505c3e" }}><div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", fontSize: 26 }}><span>Crispy Crust.</span><span style={{ fontSize: 20, color: "#505c3e" }}>THE BAKER’S JOURNAL</span></div><div style={{ display: "flex", flexDirection: "column", gap: 22 }}><div style={{ display: "flex", color: "#505c3e", fontSize: 22 }}>{topicForGuide(guide ?? guides[0])?.name.toUpperCase()}</div><div style={{ display: "flex", fontSize: (guide?.title.length ?? 0) > 85 ? 54 : 64, lineHeight: 1.08, letterSpacing: -2, maxWidth: 1030 }}>{guide?.title ?? "A little know-how for your next loaf."}</div></div><div style={{ display: "flex", justifyContent: "space-between", fontSize: 21, borderTop: "1px solid #dedfd4", paddingTop: 24 }}><span>Good bread. On your time.</span><span>crispycrust.app</span></div></div>, size);
}
