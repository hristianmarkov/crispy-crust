import { NextRequest, NextResponse } from "next/server";
import {
  appendFile,
  mkdir,
  readFile,
  writeFile,
  rename,
} from "node:fs/promises";
import path from "node:path";
import { randomUUID } from "node:crypto";
export const runtime = "nodejs";
const attempts = new Map<string, { count: number; reset: number }>();
let queue: Promise<unknown> = Promise.resolve();
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
  const now = Date.now();
  for (const [key, item] of attempts)
    if (item.reset < now) attempts.delete(key);
  const rate = attempts.get(ip) || { count: 0, reset: now + 60_000 };
  if (rate.count >= 8)
    return NextResponse.json(
      { error: "A few too many tries. Please wait a minute and try again." },
      { status: 429 },
    );
  rate.count++;
  attempts.set(ip, rate);
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
  const directory =
    process.env.WAITLIST_DATA_DIR || path.join(process.cwd(), ".data");
  const file = path.join(directory, "waitlist.jsonl");
  try {
    const write = queue.then(async () => {
      await mkdir(directory, { recursive: true, mode: 0o700 });
      let existing = "";
      try {
        existing = await readFile(file, "utf8");
      } catch (e) {
        if ((e as NodeJS.ErrnoException).code !== "ENOENT") throw e;
      }
      if (action === "remove") {
        const kept = existing
          .split("\n")
          .filter(Boolean)
          .filter((line) => JSON.parse(line).email !== normalized);
        const temporary = file + ".tmp";
        await writeFile(temporary, kept.length ? kept.join("\n") + "\n" : "", {
          mode: 0o600,
        });
        await rename(temporary, file);
        return;
      }
      if (
        !existing
          .split("\n")
          .filter(Boolean)
          .some((line) => JSON.parse(line).email === normalized)
      )
        await appendFile(
          file,
          JSON.stringify({
            id: randomUUID(),
            email: normalized,
            platform,
            consent: "launch-updates-v1",
            createdAt: new Date().toISOString(),
          }) + "\n",
          { mode: 0o600 },
        );
    });
    queue = write.catch(() => {});
    await write;
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
