import type { MediaService } from "./media.ts";
import type { BillingService } from "./billing.ts";
/** Web API router. Core RPCs forward caller auth; privileged adapters are server-only. */
export type Json = Record<string, unknown>;
export class ApiError extends Error {
  constructor(
    public code: string,
    public status = 400,
  ) {
    super(code);
  }
}
export interface Backend {
  user(token: string): Promise<{ id: string; last_sign_in_at?: string }>;
  rpc(name: string, params: Json, token: string): Promise<unknown>;
  rows(table: string, query: string, token: string): Promise<unknown>;
}
export interface RouterConfig {
  backend: Backend;
  allowedOrigins: readonly string[];
  coachEnabled: boolean;
  importEnabled: boolean;
  imageEnabled?: boolean;
  media?: MediaService;
  billing?: BillingService;
}
const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
export function uuid(value: unknown): string {
  if (typeof value !== "string" || !UUID.test(value))
    throw new ApiError("INVALID_UUID");
  return value;
}
function string(value: unknown, max = 500): string {
  if (typeof value !== "string" || !value.trim() || value.length > max)
    throw new ApiError("INVALID_TEXT");
  return value;
}
function object(value: unknown): Json {
  if (!value || typeof value !== "object" || Array.isArray(value))
    throw new ApiError("INVALID_OBJECT");
  return value as Json;
}
function number(value: unknown, min: number, max: number): number {
  const n = Number(value);
  if (!Number.isSafeInteger(n) || n < min || n > max)
    throw new ApiError("INVALID_INTEGER");
  return n;
}
function only(body: Json, keys: string[]) {
  if (Object.keys(body).some((k) => !keys.includes(k)))
    throw new ApiError("UNEXPECTED_FIELD");
}
async function jsonBody(req: Request): Promise<Json> {
  if (
    !req.headers
      .get("content-type")
      ?.toLowerCase()
      .startsWith("application/json")
  )
    throw new ApiError("JSON_REQUIRED", 415);
  const max = 1048576;
  if (Number(req.headers.get("content-length") || 0) > max)
    throw new ApiError("REQUEST_TOO_LARGE", 413);
  if (!req.body) throw new ApiError("BODY_REQUIRED");
  const reader = req.body.getReader();
  const chunks: Uint8Array[] = [];
  let bytes = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      bytes += value.byteLength;
      if (bytes > max) {
        await reader.cancel();
        throw new ApiError("REQUEST_TOO_LARGE", 413);
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const merged = new Uint8Array(bytes);
  let i = 0;
  for (const chunk of chunks) {
    merged.set(chunk, i);
    i += chunk.length;
  }
  try {
    return object(
      JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(merged)),
    );
  } catch (e) {
    if (e instanceof ApiError) throw e;
    throw new ApiError("INVALID_JSON");
  }
}
export function createRouter(config: RouterConfig) {
  return async (req: Request): Promise<Response> => {
    const requestId = crypto.randomUUID();
    const origin = req.headers.get("origin");
    let headers: Record<string, string> = {
      "content-type": "application/json",
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
      "x-request-id": requestId,
    };
    if (origin && config.allowedOrigins.includes(origin))
      headers = {
        ...headers,
        "access-control-allow-origin": origin,
        vary: "Origin",
        "access-control-allow-headers":
          "authorization, apikey, content-type, idempotency-key",
        "access-control-allow-methods": "GET,POST,DELETE,OPTIONS",
      };
    const response = (data: unknown, status = 200) =>
      new Response(JSON.stringify({ data, request_id: requestId }), {
        status,
        headers,
      });
    try {
      if (origin && !config.allowedOrigins.includes(origin))
        throw new ApiError("ORIGIN_NOT_ALLOWED", 403);
      if (req.method === "OPTIONS")
        return new Response(null, { status: 204, headers });
      const authorization = req.headers.get("authorization");
      if (!authorization?.startsWith("Bearer "))
        throw new ApiError("AUTH_REQUIRED", 401);
      const token = authorization.slice(7);
      const user = await config.backend.user(token);
      uuid(user.id);
      const path =
        new URL(req.url).pathname.replace(/^.*\/app-api(?:\/v1)?/, "") || "/";
      const url = new URL(req.url);
      if (req.method === "GET") {
        const mediaRead = path.match(/^\/media\/([^/]+)\/download$/);
        if (mediaRead) {
          if (!config.media)
            throw new ApiError("MEDIA_VERIFICATION_NOT_CONFIGURED", 503);
          return response(await config.media.read(uuid(mediaRead[1]), token));
        }
        if (path === "/community/feed" || path === "/community/mine")
          return response(
            await config.backend.rows(
              "cc_posts",
              `select=id,author_id,title,status,snapshot,created_at&${path.endsWith("mine") ? "author_id=eq." + user.id : "status=eq.published"}&order=created_at.desc,id.desc&limit=50`,
              token,
            ),
          );
        const commentList = path.match(
          /^\/community\/posts\/([^/]+)\/comments$/,
        );
        if (commentList)
          return response(
            await config.backend.rows(
              "cc_comments",
              `post_id=eq.${uuid(commentList[1])}&select=id,author_id,body,status,created_at&order=created_at.asc,id.asc&limit=100`,
              token,
            ),
          );
        if (path === "/staff/reports")
          return response(
            await config.backend.rpc("cc_staff_reports", {}, token),
          );
        if (path === "/staff/pending")
          return response(
            await config.backend.rpc("cc_staff_pending", {}, token),
          );

        if (path === "/sync/pull")
          return response(
            await config.backend.rpc(
              "cc_sync_pull",
              {
                p_kitchen: uuid(url.searchParams.get("kitchen_id")),
                p_cursor: number(
                  url.searchParams.get("cursor") ?? 0,
                  0,
                  Number.MAX_SAFE_INTEGER,
                ),
                p_limit: number(url.searchParams.get("limit") ?? 100, 1, 500),
              },
              token,
            ),
          );
        const memberList = path.match(/^\/kitchens\/([^/]+)\/members$/);
        if (memberList)
          return response(
            await config.backend.rpc(
              "cc_list_members",
              { p_kitchen: uuid(memberList[1]) },
              token,
            ),
          );
        if (path === "/kitchens")
          return response(
            await config.backend.rows(
              "cc_kitchens",
              "select=id,name,kind,membership_revision,change_sequence",
              token,
            ),
          );
        const job = path.match(/^\/jobs\/([^/]+)$/);
        if (job)
          return response(
            await config.backend.rows(
              "cc_jobs",
              `id=eq.${uuid(job[1])}&select=id,kind,status,result,error_code,created_at`,
              token,
            ),
          );
        const share = path.match(/^\/shares\/([^/]+)$/);
        if (share)
          return response(
            await config.backend.rpc(
              "cc_read_share",
              { p_token: string(decodeURIComponent(share[1]), 150) },
              token,
            ),
          );
        throw new ApiError("NOT_FOUND", 404);
      }
      if (req.method === "DELETE") {
        const mediaDelete = path.match(/^\/media\/([^/]+)$/);
        if (mediaDelete) {
          if (!config.media)
            throw new ApiError("MEDIA_VERIFICATION_NOT_CONFIGURED", 503);
          return response(
            await config.media.remove(uuid(mediaDelete[1]), token),
          );
        }
        const share = path.match(/^\/shares\/([^/]+)$/);
        if (share)
          return response(
            await config.backend.rpc(
              "cc_revoke_share",
              { p_share: uuid(share[1]) },
              token,
            ),
          );
        throw new ApiError("NOT_FOUND", 404);
      }
      if (req.method !== "POST") throw new ApiError("METHOD_NOT_ALLOWED", 405);
      const operation = uuid(req.headers.get("idempotency-key"));
      const body = await jsonBody(req);
      const rpc = (name: string, params: Json) =>
        config.backend.rpc(name, params, token);
      if (path === "/community/posts") {
        only(body, ["share_id", "title"]);
        return response(
          await rpc("cc_publish_post", {
            p_share: uuid(body.share_id),
            p_title: string(body.title, 160),
            p_operation: operation,
          }),
          201,
        );
      }
      const commentPost = path.match(/^\/community\/posts\/([^/]+)\/comments$/);
      if (commentPost) {
        only(body, ["body"]);
        return response(
          await rpc("cc_comment", {
            p_post: uuid(commentPost[1]),
            p_body: string(body.body, 2000),
            p_operation: operation,
          }),
          201,
        );
      }
      if (path === "/community/follows") {
        only(body, ["creator_id", "following"]);
        if (typeof body.following !== "boolean")
          throw new ApiError("INVALID_BOOLEAN");
        return response(
          await rpc("cc_follow", {
            p_creator: uuid(body.creator_id),
            p_following: body.following,
          }),
        );
      }
      if (path === "/staff/moderate") {
        only(body, ["target_type", "target_id", "action", "reason"]);
        return response(
          await rpc("cc_moderate", {
            p_type: string(body.target_type, 20),
            p_target: uuid(body.target_id),
            p_action: string(body.action, 20),
            p_reason: string(body.reason, 500),
          }),
        );
      }
      if (path === "/staff/reports/resolve") {
        only(body, ["report_id", "resolution"]);
        return response(
          await rpc("cc_resolve_report", {
            p_report: uuid(body.report_id),
            p_resolution: string(body.resolution, 20),
          }),
        );
      }
      if (path === "/members/role") {
        only(body, ["kitchen_id", "user_id", "role"]);
        return response(
          await rpc("cc_set_role", {
            p_kitchen: uuid(body.kitchen_id),
            p_user: uuid(body.user_id),
            p_role: string(body.role, 10),
          }),
        );
      }
      if (path === "/kitchens/transfer") {
        only(body, ["kitchen_id", "user_id"]);
        if (
          !user.last_sign_in_at ||
          Date.now() - Date.parse(user.last_sign_in_at) > 300000
        )
          throw new ApiError("REAUTH_REQUIRED", 401);
        return response(
          await rpc("cc_transfer_owner", {
            p_kitchen: uuid(body.kitchen_id),
            p_user: uuid(body.user_id),
          }),
        );
      }
      if (path === "/account/bootstrap") {
        only(body, ["display_name"]);
        return response(
          await rpc("cc_bootstrap", { p_name: body.display_name ?? null }),
        );
      }
      if (path === "/kitchens") {
        only(body, ["kind", "name"]);
        return response(
          await rpc("cc_create_kitchen", {
            p_kind: string(body.kind, 20),
            p_name: string(body.name, 100),
          }),
          201,
        );
      }
      if (path === "/sync/push") {
        only(body, [
          "kitchen_id",
          "device_id",
          "membership_revision",
          "operations",
        ]);
        if (!Array.isArray(body.operations) || body.operations.length > 100)
          throw new ApiError("INVALID_BATCH");
        return response(
          await rpc("cc_sync_push", {
            p_kitchen: uuid(body.kitchen_id),
            p_device: uuid(body.device_id),
            p_operations: body.operations,
          }),
        );
      }
      const plan = path.match(/^\/bakes\/([^/]+)\/accept-plan$/);
      if (plan) {
        only(body, ["kitchen_id", "expected_bake_revision", "snapshot"]);
        return response(
          await rpc("cc_accept_plan", {
            p_kitchen: uuid(body.kitchen_id),
            p_bake: uuid(plan[1]),
            p_operation: operation,
            p_expected_revision: number(
              body.expected_bake_revision,
              1,
              Number.MAX_SAFE_INTEGER,
            ),
            p_snapshot: object(body.snapshot),
          }),
        );
      }
      const invite = path.match(/^\/kitchens\/([^/]+)\/invite$/);
      if (invite) {
        only(body, ["role", "expires_in_seconds"]);
        return response(
          await rpc("cc_create_invite", {
            p_kitchen: uuid(invite[1]),
            p_role: string(body.role, 10),
            p_expires_seconds: number(
              body.expires_in_seconds ?? 604800,
              60,
              604800,
            ),
          }),
          201,
        );
      }
      if (path === "/invites/redeem") {
        only(body, ["token"]);
        return response(
          await rpc("cc_redeem_invite", { p_token: string(body.token, 150) }),
        );
      }
      if (path === "/members/revoke") {
        only(body, ["kitchen_id", "user_id"]);
        return response(
          await rpc("cc_revoke_member", {
            p_kitchen: uuid(body.kitchen_id),
            p_user: uuid(body.user_id),
          }),
        );
      }
      if (path === "/shares") {
        only(body, [
          "kitchen_id",
          "source_id",
          "selected_fields",
          "expires_at",
          "expected_source_revision",
        ]);
        if (
          !Array.isArray(body.selected_fields) ||
          body.selected_fields.some((x) => typeof x !== "string")
        )
          throw new ApiError("INVALID_FIELDS");
        return response(
          await rpc("cc_create_share", {
            p_kitchen: uuid(body.kitchen_id),
            p_aggregate: uuid(body.source_id),
            p_fields: body.selected_fields,
            p_expires_at: body.expires_at ?? null,
            p_expected_revision: number(
              body.expected_source_revision,
              1,
              Number.MAX_SAFE_INTEGER,
            ),
          }),
          201,
        );
      }
      if (path === "/consents") {
        only(body, ["purpose", "version", "granted"]);
        if (typeof body.granted !== "boolean")
          throw new ApiError("INVALID_BOOLEAN");
        return response(
          await rpc("cc_grant_consent", {
            p_purpose: string(body.purpose, 20),
            p_version: string(body.version, 50),
            p_granted: body.granted,
          }),
        );
      }
      if (
        path === "/coach/requests" ||
        path === "/imports" ||
        path === "/exports"
      ) {
        const kind =
          path === "/imports"
            ? "import"
            : path === "/exports"
              ? "export"
              : "coach";
        if (kind === "coach" && !config.coachEnabled)
          throw new ApiError("AI_PROVIDER_NOT_CONFIGURED", 503);
        if (kind === "import" && !config.importEnabled)
          throw new ApiError("IMPORT_PROVIDER_NOT_CONFIGURED", 503);
        only(body, [
          "kitchen_id",
          "consent_version",
          "question",
          "context",
          "source",
          "scope",
          "format",
          "selected_ids",
          "include_media",
        ]);
        // Context IDs are read under caller RLS; uploaded context is explicit, never whole library.
        if (body.context) {
          const c = object(body.context);
          only(c, ["aggregate_ids", "observations", "photos"]);
          if (c.photos)
            throw new ApiError("IMAGE_PIPELINE_NOT_CONFIGURED", 503);
          if (c.aggregate_ids) {
            if (!Array.isArray(c.aggregate_ids) || c.aggregate_ids.length > 10)
              throw new ApiError("CONTEXT_TOO_LARGE");
            const ids = c.aggregate_ids.map(uuid);
            const records = (await config.backend.rows(
              "cc_aggregates",
              `id=in.(${ids.join(",")})&select=id,kind,revision,data`,
              token,
            )) as unknown[];
            if (records.length !== ids.length)
              throw new ApiError("CONTEXT_NOT_FOUND", 404);
            body.context = { records, observations: c.observations ?? [] };
          }
        }
        if (kind === "coach") string(body.question, 4000);
        return response(
          await rpc("cc_enqueue_job", {
            p_operation: operation,
            p_kind: kind,
            p_input: body,
            p_kitchen: body.kitchen_id ? uuid(body.kitchen_id) : null,
          }),
          202,
        );
      }
      if (path === "/reports") {
        only(body, ["target_type", "target_id", "reason", "details"]);
        return response(
          await rpc("cc_report", {
            p_type: string(body.target_type, 20),
            p_target: uuid(body.target_id),
            p_reason: string(body.reason, 500),
            p_details: body.details ?? null,
          }),
          201,
        );
      }
      if (path === "/blocks") {
        only(body, ["user_id"]);
        return response(await rpc("cc_block", { p_user: uuid(body.user_id) }));
      }
      if (path === "/account/delete") {
        only(body, ["acknowledge_subscription_separation"]);
        if (body.acknowledge_subscription_separation !== true)
          throw new ApiError("SUBSCRIPTION_ACK_REQUIRED");
        if (
          !user.last_sign_in_at ||
          Date.now() - Date.parse(user.last_sign_in_at) > 300000
        )
          throw new ApiError("REAUTH_REQUIRED", 401);
        return response(await rpc("cc_request_delete", {}), 202);
      }
      if (path === "/purchases/verify") {
        if (!config.billing)
          throw new ApiError("STORE_VERIFICATION_NOT_CONFIGURED", 503);
        only(body, ["app_user_id"]);
        if (body.app_user_id && body.app_user_id !== user.id)
          throw new ApiError("BILLING_IDENTITY_MISMATCH", 403);
        return response(await config.billing.refresh(user.id));
      }
      if (path === "/media/uploads") {
        if (!config.media)
          throw new ApiError("MEDIA_VERIFICATION_NOT_CONFIGURED", 503);
        only(body, [
          "kitchen_id",
          "attachment_target",
          "sha256",
          "mime_type",
          "bytes",
          "width",
          "height",
        ]);
        uuid(body.kitchen_id);
        uuid(body.attachment_target);
        if (
          typeof body.sha256 !== "string" ||
          !/^[a-f0-9]{64}$/.test(body.sha256) ||
          !["image/jpeg", "image/png", "image/webp"].includes(
            String(body.mime_type),
          )
        )
          throw new ApiError("INVALID_MEDIA");
        number(body.bytes, 1, 2097152);
        number(body.width, 1, 4096);
        number(body.height, 1, 4096);
        return response(
          await config.media.prepare(body, operation, token),
          201,
        );
      }
      const mediaComplete = path.match(/^\/media\/([^/]+)\/complete$/);
      if (mediaComplete) {
        if (!config.media)
          throw new ApiError("MEDIA_VERIFICATION_NOT_CONFIGURED", 503);
        only(body, []);
        return response(
          await config.media.complete(uuid(mediaComplete[1]), token),
        );
      }
      if (path === "/analysis/requests") {
        if (!config.imageEnabled)
          throw new ApiError("IMAGE_PIPELINE_NOT_CONFIGURED", 503);
        only(body, [
          "kitchen_id",
          "consent_version",
          "question",
          "media_ids",
          "context",
        ]);
        string(body.consent_version, 50);
        if (body.question) string(body.question, 4000);
        if (
          !Array.isArray(body.media_ids) ||
          body.media_ids.length < 1 ||
          body.media_ids.length > 2 ||
          new Set(body.media_ids).size !== body.media_ids.length
        )
          throw new ApiError("INVALID_MEDIA_SELECTION");
        const ids = body.media_ids.map(uuid);
        const assets = (await config.backend.rows(
          "cc_media",
          `id=in.(${ids.join(",")})&status=eq.uploaded&select=id`,
          token,
        )) as unknown[];
        if (assets.length !== ids.length)
          throw new ApiError("MEDIA_NOT_FOUND", 404);
        if (body.context) {
          const context = object(body.context);
          only(context, ["observations"]);
        }
        return response(
          await rpc("cc_enqueue_job", {
            p_operation: operation,
            p_kind: "image",
            p_input: body,
            p_kitchen: body.kitchen_id ? uuid(body.kitchen_id) : null,
          }),
          202,
        );
      }
      throw new ApiError("NOT_FOUND", 404);
    } catch (error) {
      const e =
        error instanceof ApiError ? error : new ApiError("INTERNAL_ERROR", 500);
      return new Response(
        JSON.stringify({
          error: { code: e.code, message: e.code, retryable: e.status >= 500 },
          request_id: requestId,
        }),
        { status: e.status, headers },
      );
    }
  };
}
export class RestBackend implements Backend {
  constructor(
    private url: string,
    private key: string,
    private fetcher: typeof fetch = fetch,
  ) {
    const parsed = new URL(url);
    if (parsed.protocol !== "https:" && parsed.hostname !== "127.0.0.1")
      throw new Error("Invalid backend origin");
  }
  private async call(path: string, token: string, method = "GET", body?: Json) {
    const r = await this.fetcher(`${this.url}${path}`, {
      method,
      headers: {
        apikey: this.key,
        authorization: `Bearer ${token}`,
        "content-type": "application/json",
      },
      body: body ? JSON.stringify(body) : undefined,
      signal: AbortSignal.timeout(15000),
    });
    const data = await r.json();
    if (!r.ok) {
      let code =
        typeof data.message === "string" ? data.message : "BACKEND_UNAVAILABLE";
      if (!/^[A-Z_]+$/.test(code))
        code = r.status === 401 ? "AUTH_REQUIRED" : "BACKEND_ERROR";
      throw new ApiError(
        code,
        r.status === 409 || data.code === "23505"
          ? 409
          : r.status === 401 || data.code === "28000"
            ? 401
            : r.status === 403 || data.code === "42501"
              ? 403
              : r.status >= 500
                ? 503
                : 400,
      );
    }
    return data;
  }
  user(token: string) {
    return this.call("/auth/v1/user", token) as Promise<{
      id: string;
      last_sign_in_at?: string;
    }>;
  }
  rpc(name: string, params: Json, token: string) {
    return this.call(`/rest/v1/rpc/${name}`, token, "POST", params);
  }
  rows(table: string, query: string, token: string) {
    return this.call(`/rest/v1/${table}?${query}`, token);
  }
}
