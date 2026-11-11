import { ApiError, type Json, uuid } from "./router.ts";
import type { ServiceStore } from "./deletion.ts";
import { hashBytes } from "./media.ts";
export interface BillingConfig {
  apiKey?: string;
  webhookAuthorization?: string;
  signingSecret?: string;
  environment: "SANDBOX" | "PRODUCTION";
  entitlementKeys: readonly string[];
  fetcher?: typeof fetch;
  service: ServiceStore;
}
export interface BillingService {
  refresh(userId: string, eventId?: string, eventHash?: string): Promise<Json>;
}
export async function verifyWebhook(
  raw: Uint8Array,
  header: string | null,
  secret: string,
  now = Date.now(),
): Promise<boolean> {
  if (!header || !secret) return false;
  const parts = header.split(",").map((x) => x.trim().split("="));
  if (
    parts.length !== 2 ||
    parts.filter((x) => x[0] === "t").length !== 1 ||
    parts.filter((x) => x[0] === "v1").length !== 1
  )
    return false;
  const map = Object.fromEntries(parts);
  if (
    !/^\d{10,12}$/.test(map.t) ||
    !/^[a-f0-9]{64}$/i.test(map.v1) ||
    Math.abs(now / 1000 - Number(map.t)) > 300
  )
    return false;
  const prefix = new TextEncoder().encode(map.t + "."),
    message = new Uint8Array(prefix.length + raw.length);
  message.set(prefix);
  message.set(raw, prefix.length);
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["verify"],
  );
  const signature = new Uint8Array(
    map.v1.match(/../g)!.map((x: string) => parseInt(x, 16)),
  );
  return crypto.subtle.verify("HMAC", key, signature, message);
}
export class RevenueCatService implements BillingService {
  constructor(private config: BillingConfig) {}
  async refresh(
    userId: string,
    eventId = "refresh:" + crypto.randomUUID(),
    eventHash?: string,
  ): Promise<Json> {
    uuid(userId);
    if (!this.config.apiKey)
      throw new ApiError("STORE_VERIFICATION_NOT_CONFIGURED", 503);
    const response = await (this.config.fetcher ?? fetch)(
      "https://api.revenuecat.com/v1/subscribers/" + encodeURIComponent(userId),
      {
        headers: {
          authorization: `Bearer ${this.config.apiKey}`,
          accept: "application/json",
        },
        signal: AbortSignal.timeout(10000),
      },
    );
    if (!response.ok) throw new ApiError("STORE_PROVIDER_UNAVAILABLE", 503);
    const snapshot = (await response.json()) as Json;
    const subscriber = snapshot.subscriber as Json;
    if (
      !subscriber ||
      typeof snapshot.request_date_ms !== "number" ||
      !Number.isFinite(snapshot.request_date_ms)
    )
      throw new ApiError("STORE_RESPONSE_INVALID", 502);
    const verifiedMs = snapshot.request_date_ms as number;
    const verifiedAt = new Date(verifiedMs).toISOString();
    const entitlements = subscriber.entitlements as
      Record<string, Json> | undefined;
    const subscriptions = subscriber.subscriptions as
      Record<string, Json> | undefined;
    if (!entitlements || typeof entitlements !== "object")
      throw new ApiError("STORE_RESPONSE_INVALID", 502);
    const rows = this.config.entitlementKeys.flatMap((key) => {
      const e = entitlements[key];
      if (!e) return [];
      const product =
        typeof e.product_identifier === "string"
          ? subscriptions?.[e.product_identifier]
          : undefined;
      const sandbox = product?.is_sandbox;
      if (this.config.environment === "PRODUCTION" && sandbox !== false)
        return [];
      if (this.config.environment === "SANDBOX" && sandbox !== true) return [];
      const until =
        e.expires_date === null
          ? null
          : typeof e.expires_date === "string"
            ? Date.parse(e.expires_date)
            : NaN;
      if (until !== null && !Number.isFinite(until))
        throw new ApiError("STORE_RESPONSE_INVALID", 502);
      return [
        {
          key,
          state: until === null || until > verifiedMs ? "active" : "expired",
          valid_until: until === null ? null : new Date(until).toISOString(),
        },
      ];
    });
    const hash =
      eventHash ??
      (await hashBytes(new TextEncoder().encode(JSON.stringify(snapshot))));
    await this.config.service.rpc("cc_worker_entitlements", {
      p_user: userId,
      p_event: eventId,
      p_hash: hash,
      p_verified_at: verifiedAt,
      p_entitlements: rows,
    });
    return {
      entitlements: rows,
      verified_at: verifiedAt,
      source: "revenuecat_server",
    };
  }
}
export function billingWebhook(config: BillingConfig) {
  return async (request: Request): Promise<Response> => {
    const respond = (value: Json, status = 200) =>
      Response.json(value, {
        status,
        headers: { "cache-control": "no-store" },
      });
    try {
      if (
        !config.apiKey ||
        !config.signingSecret ||
        !config.webhookAuthorization
      )
        throw new ApiError("STORE_WEBHOOK_NOT_CONFIGURED", 503);
      if (request.method !== "POST")
        throw new ApiError("METHOD_NOT_ALLOWED", 405);
      if (request.headers.get("authorization") !== config.webhookAuthorization)
        throw new ApiError("WEBHOOK_UNAUTHORIZED", 401);
      if (Number(request.headers.get("content-length") || 0) > 262144)
        throw new ApiError("WEBHOOK_TOO_LARGE", 413);
      if (!request.body) throw new ApiError("WEBHOOK_INVALID", 400);
      const reader = request.body.getReader();
      const chunks: Uint8Array[] = [];
      let total = 0;
      try {
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          total += value.length;
          if (total > 262144) {
            await reader.cancel();
            throw new ApiError("WEBHOOK_TOO_LARGE", 413);
          }
          chunks.push(value);
        }
      } finally {
        reader.releaseLock();
      }
      const raw = new Uint8Array(total);
      let at = 0;
      for (const chunk of chunks) {
        raw.set(chunk, at);
        at += chunk.length;
      }
      if (
        !(await verifyWebhook(
          raw,
          request.headers.get("x-revenuecat-webhook-signature"),
          config.signingSecret,
        ))
      )
        throw new ApiError("WEBHOOK_SIGNATURE_INVALID", 401);
      const body = JSON.parse(new TextDecoder().decode(raw)) as Json;
      const event = body.event as Json;
      if (!event || typeof event.id !== "string" || event.id.length > 200)
        throw new ApiError("WEBHOOK_INVALID", 400);
      if (event.type === "TEST") return respond({ accepted: true, test: true });
      if (event.environment && event.environment !== config.environment)
        return respond({ accepted: true, ignored_environment: true });
      const possible = [
        event.app_user_id,
        ...(Array.isArray(event.transferred_from)
          ? event.transferred_from
          : []),
        ...(Array.isArray(event.transferred_to) ? event.transferred_to : []),
      ];
      const ids = [
        ...new Set(
          possible.filter(
            (x) => typeof x === "string" && /^[0-9a-f-]{36}$/i.test(x),
          ) as string[],
        ),
      ];
      if (ids.length > 10)
        throw new ApiError("WEBHOOK_TRANSFER_TOO_LARGE", 422);
      if (!ids.length)
        return respond({ accepted: true, unbound_identity: true });
      const hash = await hashBytes(raw);
      const service = new RevenueCatService(config);
      await Promise.all(
        ids.map((id) => service.refresh(uuid(id), event.id as string, hash)),
      );
      return respond({ accepted: true, refreshed: ids.length });
    } catch (error) {
      const e =
        error instanceof ApiError
          ? error
          : new ApiError("WEBHOOK_INVALID", 400);
      return respond(
        { error: { code: e.code, retryable: e.status >= 500 } },
        e.status,
      );
    }
  };
}
