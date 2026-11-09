import { NextRequest, NextResponse } from "next/server";
import { createHmac } from "node:crypto";
export const runtime = "nodejs";
export async function POST(req: NextRequest) {
  const origin = req.headers.get("origin");
  let sameHost = false;
  try {
    sameHost = Boolean(
      origin && new URL(origin).host === req.headers.get("host"),
    );
  } catch {}
  if (
    origin &&
    !sameHost &&
    origin !== new URL(req.url).origin &&
    origin !== process.env.NEXT_PUBLIC_SITE_URL
  )
    return NextResponse.json(
      { error: "Please submit the form from this website." },
      { status: 403 },
    );
  if (Number(req.headers.get("content-length") || 0) > 2048)
    return NextResponse.json({ error: "Request too large." }, { status: 413 });
  const ip =
    req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() || "local";
  let data: unknown;
  try {
    const text = await req.text();
    if (text.length > 2048)
      return NextResponse.json(
        { error: "Request too large." },
        { status: 413 },
      );
    data = JSON.parse(text);
  } catch {
    return NextResponse.json(
      { error: "Please enter a valid email address." },
      { status: 400 },
    );
  }
  if (!data || typeof data !== "object")
    return NextResponse.json(
      { error: "Please enter a valid email address." },
      { status: 400 },
    );
  const { email, platform, website, action } = data as Record<string, unknown>;
  if (website) return NextResponse.json({ success: true });
  if (
    typeof email !== "string" ||
    email.length > 254 ||
    !/^\S+@[^\s@]+\.[^\s@]+$/.test(email.trim()) ||
    (action !== "remove" &&
      !["ios", "android", "both"].includes(String(platform)))
  )
    return NextResponse.json(
      { error: "Please enter a valid email address and choose your platform." },
      { status: 400 },
    );
  const normalized = email.trim().toLowerCase();
  try {
    const endpoint = process.env.SUPABASE_WAITLIST_URL;
    const token = process.env.WAITLIST_SERVER_TOKEN;
    if (!endpoint || !token) throw new Error("Waitlist not configured");
    const response = await fetch(endpoint, {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-waitlist-token": token },
      body: JSON.stringify({
        email: normalized,
        platform,
        action: action === "remove" ? "remove" : "join",
        // Only a keyed daily hash reaches the database, never the raw IP.
        rateKey: createHmac("sha256", token).update(new Date().toISOString().slice(0, 10) + ":" + ip).digest("hex"),
      }),
      cache: "no-store",
      signal: AbortSignal.timeout(10000),
    });
    if (response.status === 429)
      return NextResponse.json({ error: "A few too many tries. Please wait a minute and try again." }, { status: 429 });
    if (!response.ok) throw new Error("Waitlist storage unavailable");
    return NextResponse.json({ success: true });
  } catch {
    console.error("Waitlist storage unavailable");
    return NextResponse.json(
      {
        error: "We couldn’t save your spot just now. Please try again shortly.",
      },
      { status: 503 },
    );
  }
}
