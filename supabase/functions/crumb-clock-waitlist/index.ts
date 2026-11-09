// Server-to-server only. No browser CORS access or database key exposure.
const expectedTokenHash = "266b0f8a0a24c2f35444c3782fee9587bad0b0ddea1a7bf9bb09271899e0c764";
const json = (body: unknown, status = 200) => Response.json(body, { status });
Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const token = req.headers.get("x-waitlist-token") ?? "";
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token));
  const hash = Array.from(new Uint8Array(digest), b => b.toString(16).padStart(2,"0")).join("");
  if (hash !== expectedTokenHash) return json({ error: "Unauthorized" }, 401);
  try {
    const text = await req.text();
    if (text.length > 2048) return json({ error: "Request too large" }, 413);
    const data = JSON.parse(text);
    const url = Deno.env.get("SUPABASE_URL")!;
    const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const result = await fetch(`${url}/rest/v1/rpc/crumb_clock_waitlist_request`, {
      method: "POST",
      headers: { "Content-Type": "application/json", apikey: key, Authorization: `Bearer ${key}` },
      body: JSON.stringify({ p_email: data.email, p_platform: data.platform ?? null, p_action: data.action, p_rate_key: data.rateKey }),
      signal: AbortSignal.timeout(8000),
    });
    if (!result.ok) { console.error("Waitlist database request failed", result.status); return json({ error: "Storage unavailable" }, 503); }
    if (await result.json() !== true) return json({ error: "Too many requests" }, 429);
    return json({ success: true });
  } catch { return json({ error: "Invalid or unavailable request" }, 503); }
});
