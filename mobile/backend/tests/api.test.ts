import { test } from "node:test";
import assert from "node:assert/strict";
import {
  createRouter,
  ApiError,
  type Backend,
  type Json,
} from "../functions/app-api/router.ts";
import {
  publicAddress,
  validateImportUrl,
  importRecipe,
  coachAnswer,
  runJobs,
  type ProviderConfig,
} from "../functions/app-api/jobs.ts";
const U = "11111111-1111-4111-8111-111111111111";
const calls: { name: string; params: Json }[] = [];
const backend: Backend = {
  user: async (token) => {
    if (token !== "valid") throw new ApiError("AUTH_REQUIRED", 401);
    return { id: U, last_sign_in_at: new Date().toISOString() };
  },
  rpc: async (name, params) => {
    calls.push({ name, params });
    return { name, ...params };
  },
  rows: async () => [],
};
const router = createRouter({
  backend,
  allowedOrigins: ["https://trusted.test"],
  coachEnabled: false,
  importEnabled: false,
});
const request = (
  path: string,
  body: unknown = {},
  headers: Record<string, string> = {},
) =>
  new Request("https://backend.test/functions/v1/app-api/v1" + path, {
    method: "POST",
    headers: {
      authorization: "Bearer valid",
      "idempotency-key": U,
      "content-type": "application/json",
      ...headers,
    },
    body: JSON.stringify(body),
  });
test("requires verified Auth token, exact origin and real operation ID", async () => {
  assert.equal(
    (
      await router(
        request("/account/bootstrap", {}, { authorization: "Bearer forged" }),
      )
    ).status,
    401,
  );
  assert.equal(
    (
      await router(
        request("/account/bootstrap", {}, { origin: "https://evil.test" }),
      )
    ).status,
    403,
  );
  assert.equal(
    (
      await router(
        request("/account/bootstrap", {}, { "idempotency-key": "not-uuid" }),
      )
    ).status,
    400,
  );
  assert.equal(
    (await router(request("/account/bootstrap", { display_name: "Alice" })))
      .status,
    200,
  );
});
test("rejects privileged unexpected fields and oversized JSON", async () => {
  assert.equal(
    (await router(request("/account/bootstrap", { admin: true }))).status,
    400,
  );
  assert.equal(
    (
      await router(
        request("/account/bootstrap", { display_name: "x".repeat(1100000) }),
      )
    ).status,
    413,
  );
});
test("routes constrained sync params to token-scoped RPC", async () => {
  let r = await router(
    request("/sync/push", { kitchen_id: U, device_id: U, operations: [] }),
  );
  assert.equal(r.status, 200);
  assert.equal(calls.at(-1)?.name, "cc_sync_push");
  let pull = await router(
    new Request(
      `https://backend.test/functions/v1/app-api/v1/sync/pull?kitchen_id=${U}&limit=1000`,
      { headers: { authorization: "Bearer valid" } },
    ),
  );
  assert.equal(pull.status, 400);
});
test("unconfigured AI/import/purchases/media fail explicitly", async () => {
  for (const p of [
    "/coach/requests",
    "/imports",
    "/purchases/verify",
    "/media/uploads",
  ])
    assert.equal((await router(request(p))).status, 503);
});
test("account deletion requires recent reauthentication and subscription acknowledgement", async () => {
  assert.equal((await router(request("/account/delete", {}))).status, 400);
  assert.equal(
    (
      await router(
        request("/account/delete", {
          acknowledge_subscription_separation: true,
        }),
      )
    ).status,
    202,
  );
  const stale = createRouter({
    backend: {
      ...backend,
      user: async () => ({ id: U, last_sign_in_at: "2020-01-01T00:00:00Z" }),
    },
    allowedOrigins: [],
    coachEnabled: false,
    importEnabled: false,
  });
  assert.equal(
    (
      await stale(
        request("/account/delete", {
          acknowledge_subscription_separation: true,
        }),
      )
    ).status,
    401,
  );
});
test("SSRF guard rejects loopback/private/mapped/metadata/reserved and untrusted hosts", async () => {
  for (const a of [
    "127.0.0.1",
    "10.1.2.3",
    "169.254.169.254",
    "192.168.1.2",
    "172.16.1.2",
    "100.64.0.1",
    "0.0.0.0",
    "::1",
    "::ffff:127.0.0.1",
    "fc00::1",
    "2001:db8::1",
    "255.255.255.255",
  ])
    assert.equal(publicAddress(a), false, a);
  assert.equal(publicAddress("8.8.8.8"), true);
  assert.equal(publicAddress("2606:4700::1111"), true);
  for (const u of [
    "http://recipes.test/a",
    "https://x:y@recipes.test/a",
    "https://recipes.test:8443/a",
    "https://evil.test/a",
    "https://recipes.test/a#fragment",
  ])
    await assert.rejects(
      validateImportUrl(u, ["recipes.test"], async () => ["8.8.8.8"]),
      /IMPORT_FETCH_BLOCKED/,
    );
  await assert.rejects(
    validateImportUrl("https://recipes.test/a", ["recipes.test"], async () => [
      "127.0.0.1",
    ]),
    /IMPORT_FETCH_BLOCKED/,
  );
});
const config: ProviderConfig = {
  allowedImportHosts: ["recipes.test"],
  resolve: async () => ["8.8.8.8"],
};
test("recipe import produces reviewed draft, rejects redirect and retains attribution", async () => {
  const c = {
    ...config,
    fetcher: async () =>
      new Response(
        '<script type="application/ld+json">{"@type":"Recipe","name":"Country","recipeIngredient":["500g flour"]}</script>',
        { headers: { "content-type": "text/html" } },
      ),
  };
  const result = await importRecipe(
    { kind: "url", url: "https://recipes.test/bread" },
    c,
  );
  assert.equal(result.status, "draft");
  assert.equal(result.ready_to_plan, false);
  assert.equal(result.source_uri, "https://recipes.test/bread");
  assert.equal(result.title, "Country");
  await assert.rejects(
    importRecipe(
      { kind: "url", url: "https://recipes.test/a" },
      {
        ...config,
        fetcher: async () =>
          new Response(null, {
            status: 302,
            headers: { location: "https://127.0.0.1" },
          }),
      },
    ),
    /IMPORT_REDIRECT_BLOCKED/,
  );
});
test("model adapter requests no storage, validates structured output and grants no plan authority", async () => {
  let payload: any;
  const result = await coachAnswer(
    { question: "What should I check?", context: { observations: [] } },
    {
      ...config,
      apiKey: "test-key",
      model: "configured-model",
      fetcher: async (_u, init) => {
        payload = JSON.parse(init?.body as string);
        return Response.json({
          output: [
            {
              content: [
                {
                  type: "output_text",
                  text: JSON.stringify({
                    observations: ["Rise recorded"],
                    possibilities: ["Cool dough"],
                    next_check: "Measure rise",
                    uncertainty: "Temperature is missing",
                  }),
                },
              ],
            },
          ],
        });
      },
    },
  );
  assert.equal(payload.store, false);
  assert.equal(result.may_change_plan, false);
  assert.deepEqual(result.proposals, []);
  assert.deepEqual(result.reviewed_source_ids, []);
  await assert.rejects(
    coachAnswer({ question: "Help" }, { ...config }),
    /AI_PROVIDER_NOT_CONFIGURED/,
  );
  await assert.rejects(
    coachAnswer(
      { question: "Help" },
      {
        ...config,
        apiKey: "k",
        model: "m",
        fetcher: async () => Response.json({ output: [] }),
      },
    ),
    /AI_OUTPUT_INVALID/,
  );
});
test("worker records provider failures and explicitly blocks unconfigured deletion processor", async () => {
  const finished: any[] = [];
  const results = await runJobs(
    {
      claim: async () => [
        { id: U, lease_token: U, kind: "coach", input: { question: "Help" } },
        { id: U, lease_token: U, kind: "delete_account", input: {} },
      ],
      finish: async (j, r, e, retry) => {
        finished.push({ result: r, error: e, retry });
        return true;
      },
    },
    config,
  );
  assert.equal(results.length, 2);
  assert.equal(finished[0].error, "AI_PROVIDER_NOT_CONFIGURED");
  assert.equal(finished[1].error, "DELETION_PROCESSOR_NOT_CONFIGURED");
  assert.equal(finished[0].retry, false);
});

test("account deletion processor deletes objects before app state then Auth and safely retries", async () => {
  const { deleteAccount, RestServiceStore } =
    await import("../functions/app-api/deletion.ts");
  const order: string[] = [];
  const service = {
    rpc: async (name: string) => {
      order.push(name);
      return name === "cc_worker_deletion_keys"
        ? ["a.jpg", "b.jpg"]
        : { purged: true };
    },
    removeObjects: async (keys: string[]) => {
      order.push("objects:" + keys.length);
    },
    removeAuthUser: async (id: string) => {
      assert.equal(id, U);
      order.push("auth");
    },
  };
  const job = {
    id: U,
    user_id: U,
    lease_token: U,
    kind: "delete_account",
    input: {},
  };
  assert.equal((await deleteAccount(job, service)).auth_deleted, true);
  assert.deepEqual(order, [
    "cc_worker_deletion_keys",
    "objects:2",
    "cc_worker_delete_data",
    "auth",
  ]);
  const requests: any[] = [];
  const rest = new RestServiceStore(
    "https://backend.test",
    "server-secret",
    async (url, init) => {
      requests.push({ url, init });
      return new Response(null, { status: 204 });
    },
  );
  await rest.removeObjects(["a.jpg"]);
  await rest.removeAuthUser(U);
  assert.equal(requests.length, 2);
  assert.ok(requests[0].url.endsWith("/storage/v1/object/kitchen-media"));
});
test("community and staff endpoints route to commands, preserving pending moderation", async () => {
  assert.equal(
    (
      await router(
        request("/community/posts", { share_id: U, title: "My bread" }),
      )
    ).status,
    201,
  );
  assert.equal(calls.at(-1)?.name, "cc_publish_post");
  assert.equal(
    (
      await router(
        request("/staff/moderate", {
          target_type: "post",
          target_id: U,
          action: "publish",
          reason: "Reviewed",
        }),
      )
    ).status,
    200,
  );
  assert.equal(calls.at(-1)?.name, "cc_moderate");
  assert.equal(
    (
      await router(
        request("/shares", {
          kitchen_id: U,
          source_id: U,
          selected_fields: ["title"],
          expected_source_revision: 1,
        }),
      )
    ).status,
    201,
  );
  assert.equal(calls.at(-1)?.params.p_expected_revision, 1);
});

test("runtime wires media and billing adapters only with server configuration", async () => {
  const { runtimeConfig } = await import("../functions/app-api/runtime.ts");
  const values: Record<string, string> = {
    SUPABASE_URL: "https://backend.test",
    SUPABASE_ANON_KEY: "public-key",
    SUPABASE_SERVICE_ROLE_KEY: "server-only",
    REVENUECAT_API_KEY: "revenuecat-secret",
    REVENUECAT_ENTITLEMENT_KEYS: "pro",
    REVENUECAT_ENVIRONMENT: "SANDBOX",
    MEDIA_UPLOADS_ENABLED: "true",
    IMAGE_JOBS_ENABLED: "true",
    AI_JOBS_ENABLED: "true",
    IMPORT_JOBS_ENABLED: "true",
  };
  const configured = runtimeConfig((name) => values[name]);
  assert.ok(configured.media);
  assert.ok(configured.billing);
  assert.equal(configured.imageEnabled, true);
  assert.equal(configured.coachEnabled, true);
  assert.equal(configured.importEnabled, true);
  const withoutKey = runtimeConfig((name) =>
    name === "SUPABASE_SERVICE_ROLE_KEY" ? undefined : values[name],
  );
  assert.equal(withoutKey.media, undefined);
  assert.equal(withoutKey.billing, undefined);
  assert.equal(withoutKey.imageEnabled, false);
  assert.equal(withoutKey.coachEnabled, false);
  assert.equal(withoutKey.importEnabled, false);
  const disabled = runtimeConfig((name) =>
    name.endsWith("_ENABLED") ? "false" : values[name],
  );
  assert.equal(disabled.media, undefined);
  assert.equal(disabled.imageEnabled, false);
  const invalidFlag = runtimeConfig((name) =>
    name === "MEDIA_UPLOADS_ENABLED" ? "TRUE" : values[name],
  );
  assert.equal(invalidFlag.media, undefined);
});
