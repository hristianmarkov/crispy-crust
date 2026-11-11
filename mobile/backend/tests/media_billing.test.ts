import { test } from "node:test";
import assert from "node:assert/strict";
import {
  inspectImage,
  hashBytes,
  RestMediaService,
  type Asset,
} from "../functions/app-api/media.ts";
import {
  verifyWebhook,
  billingWebhook,
  RevenueCatService,
  type BillingConfig,
} from "../functions/app-api/billing.ts";
import {
  createRouter,
  type Backend,
  type Json,
} from "../functions/app-api/router.ts";
import { imageAnswer } from "../functions/app-api/jobs.ts";
const U = "11111111-1111-4111-8111-111111111111";
const png = new Uint8Array(
  Buffer.from(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aL1sAAAAASUVORK5CYII=",
    "base64",
  ),
);
const asset: Asset = {
  id: U,
  object_key: "kitchen/asset",
  sha256: await hashBytes(png),
  bytes: png.length,
  mime_type: "image/png",
  width: 1,
  height: 1,
  status: "pending",
};
const store = {
  rpc: async () => true,
  removeObjects: async () => {},
  removeAuthUser: async () => {},
};
test("image container gate measures PNG and rejects wrong MIME, metadata and oversized dimensions", () => {
  assert.deepEqual(inspectImage(png, "image/png"), { width: 1, height: 1 });
  assert.throws(() => inspectImage(png, "image/jpeg"), /MEDIA_TYPE_MISMATCH/);
  const metadata = new Uint8Array(png.length + 13);
  metadata.set(png.slice(0, -12));
  const at = png.length - 12;
  new DataView(metadata.buffer).setUint32(at, 1);
  metadata.set(new TextEncoder().encode("eXIf"), at + 4);
  metadata.set(png.slice(-12), at + 13);
  assert.throws(
    () => inspectImage(metadata, "image/png"),
    /MEDIA_METADATA_REJECTED/,
  );
  const huge = new Uint8Array(png);
  new DataView(huge.buffer).setUint32(16, 9000);
  assert.throws(
    () => inspectImage(huge, "image/png"),
    /MEDIA_DIMENSIONS_INVALID/,
  );
});
test("signed upload is caller-checked and size/hash/container verification precedes publication", async () => {
  const mutations: Json[] = [];
  const backend: Backend = {
    user: async () => ({ id: U }),
    rows: async () => [],
    rpc: async (name, params) => {
      if (name === "cc_media_prepare")
        return { asset_id: U, object_key: asset.object_key, status: "pending" };
      assert.equal(name, "cc_media_for_verify");
      return asset;
    },
  };
  const service = {
    ...store,
    rpc: async (_n: string, p: Json) => {
      mutations.push(p);
      return true;
    },
  };
  const media = new RestMediaService(
    backend,
    service,
    "https://backend.test",
    "secret",
    async (url, init) =>
      String(url).includes("/upload/sign/")
        ? Response.json({
            url: "/object/upload/sign/kitchen-media/kitchen/asset?token=signed",
          })
        : new Response(png, { headers: { "content-type": "image/png" } }),
  );
  let prepared = await media.prepare({}, U, "caller");
  assert.ok(
    String(prepared.upload_url).startsWith(
      "https://backend.test/storage/v1/object/upload/sign/",
    ),
  );
  const result = await media.complete(U, "caller");
  assert.equal(result.status, "uploaded");
  assert.equal(mutations[0].p_status, "uploaded");
});
test("hash mismatch quarantines and removes object; no false uploaded state", async () => {
  let state = "",
    removed = false;
  const backend: Backend = {
    user: async () => ({ id: U }),
    rows: async () => [],
    rpc: async () => ({ ...asset, sha256: "0".repeat(64) }),
  };
  const media = new RestMediaService(
    backend,
    {
      ...store,
      rpc: async (_n, p) => {
        state = String(p.p_status);
        return true;
      },
      removeObjects: async () => {
        removed = true;
      },
    },
    "https://backend.test",
    "secret",
    async () => new Response(png),
  );
  await assert.rejects(media.complete(U, "caller"), /MEDIA_HASH_MISMATCH/);
  assert.equal(state, "quarantined");
  assert.equal(removed, true);
});
async function signature(
  raw: string,
  secret: string,
  t = Math.floor(Date.now() / 1000),
) {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const bytes = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(t + "." + raw),
  );
  return (
    "t=" +
    t +
    ",v1=" +
    [...new Uint8Array(bytes)]
      .map((x) => x.toString(16).padStart(2, "0"))
      .join("")
  );
}
test("RevenueCat HMAC verifies raw bytes and recent delivery timestamp; rejects replay/tamper/duplicates", async () => {
  const raw = '{ "event": { "id": "x" } }',
    secret = "signing-secret";
  assert.equal(
    await verifyWebhook(
      new TextEncoder().encode(raw),
      await signature(raw, secret),
      secret,
    ),
    true,
  );
  assert.equal(
    await verifyWebhook(
      new TextEncoder().encode(JSON.stringify(JSON.parse(raw))),
      await signature(raw, secret),
      secret,
    ),
    false,
  );
  assert.equal(
    await verifyWebhook(
      new TextEncoder().encode(raw),
      await signature(raw, secret, 1),
      secret,
    ),
    false,
  );
  assert.equal(
    await verifyWebhook(
      new TextEncoder().encode(raw),
      (await signature(raw, secret)) + ",t=1234",
      secret,
    ),
    false,
  );
});
const now = Date.now();
const subscriber = {
  request_date_ms: now,
  subscriber: {
    entitlements: {
      pro: {
        product_identifier: "annual",
        expires_date: new Date(now + 86400000).toISOString(),
      },
    },
    subscriptions: { annual: { is_sandbox: false } },
  },
};
test("entitlement refresh reads bound subscriber server-side and writes only verified provider snapshot", async () => {
  let write: Json | undefined;
  const config: BillingConfig = {
    apiKey: "server-api-key",
    environment: "PRODUCTION",
    entitlementKeys: ["pro"],
    service: {
      ...store,
      rpc: async (_n, p) => {
        write = p;
        return { applied: true };
      },
    },
    fetcher: async (url, init) => {
      assert.equal(
        String(url),
        "https://api.revenuecat.com/v1/subscribers/" + U,
      );
      assert.equal(
        (init?.headers as Json).authorization,
        "Bearer server-api-key",
      );
      return Response.json(subscriber);
    },
  };
  const result = await new RevenueCatService(config).refresh(U);
  assert.equal((result.entitlements as Json[])[0].state, "active");
  assert.equal(write?.p_user, U);
  await assert.rejects(
    new RevenueCatService({ ...config, apiKey: undefined }).refresh(U),
    /STORE_VERIFICATION_NOT_CONFIGURED/,
  );
  const sandbox = structuredClone(subscriber);
  sandbox.subscriber.subscriptions.annual.is_sandbox = true;
  assert.equal(
    (
      (
        await new RevenueCatService({
          ...config,
          fetcher: async () => Response.json(sandbox),
        }).refresh(U)
      ).entitlements as unknown[]
    ).length,
    0,
  );
});
test("signed webhook authenticates both headers, ignores sandbox and re-reads current provider state", async () => {
  let reads = 0;
  const config: BillingConfig = {
    apiKey: "server",
    webhookAuthorization: "Bearer webhook",
    signingSecret: "signing",
    environment: "PRODUCTION",
    entitlementKeys: ["pro"],
    service: store,
    fetcher: async () => {
      reads++;
      return Response.json(subscriber);
    },
  };
  const handler = billingWebhook(config);
  const raw = JSON.stringify({
    event: {
      id: "event-1",
      environment: "PRODUCTION",
      app_user_id: U,
      type: "RENEWAL",
    },
  });
  const req = async (auth = "Bearer webhook") =>
    new Request("https://backend.test/functions/v1/revenuecat-webhook", {
      method: "POST",
      headers: {
        authorization: auth,
        "x-revenuecat-webhook-signature": await signature(raw, "signing"),
        "content-type": "application/json",
      },
      body: raw,
    });
  assert.equal((await handler(await req("wrong"))).status, 401);
  assert.equal(reads, 0);
  assert.equal((await handler(await req())).status, 200);
  assert.equal(reads, 1);
  const tampered = await req();
  tampered.headers.set(
    "x-revenuecat-webhook-signature",
    "t=1,v1=" + "a".repeat(64),
  );
  assert.equal((await handler(tampered)).status, 401);
});
test("image jobs send only consent-checked verified private bytes and return no confirmed measurements", async () => {
  let modelBody: any;
  const result = await imageAnswer(
    {
      id: U,
      user_id: U,
      lease_token: U,
      kind: "image",
      input: {
        question: "What can I observe?",
        consent_version: "1",
        media_ids: [U],
      },
    },
    {
      apiKey: "key",
      model: "configured",
      allowedImportHosts: [],
      resolve: async () => [],
      service: {
        ...store,
        rpc: async () => [{ ...asset, status: "uploaded" }],
      },
      media: {
        prepare: async () => ({}),
        complete: async () => ({}),
        read: async () => ({}),
        remove: async () => ({}),
        download: async () => png,
      },
      fetcher: async (_u, init) => {
        modelBody = JSON.parse(init?.body as string);
        return Response.json({
          output: [
            {
              content: [
                {
                  type: "output_text",
                  text: JSON.stringify({
                    observations: ["Visible crumb"],
                    possibilities: ["Several explanations"],
                    next_check: "Measure rise",
                    uncertainty: "Not a food safety assessment",
                  }),
                },
              ],
            },
          ],
        });
      },
    },
  );
  assert.equal(modelBody.store, false);
  assert.ok(
    modelBody.input[0].content[1].image_url.startsWith(
      "data:image/png;base64,",
    ),
  );
  assert.equal(result.requires_human_review, true);
  assert.deepEqual(result.confirmed_measurements, []);
});
test("purchase route refuses client identity substitution and image/media require configured capabilities", async () => {
  const backend: Backend = {
    user: async () => ({ id: U }),
    rows: async () => [{ id: U }],
    rpc: async () => ({}),
  };
  const router = createRouter({
    backend,
    allowedOrigins: [],
    coachEnabled: false,
    importEnabled: false,
    billing: { refresh: async (id) => ({ verified: id }) },
    imageEnabled: true,
  });
  const req = (path: string, body: Json) =>
    new Request("https://backend.test/functions/v1/app-api/v1" + path, {
      method: "POST",
      headers: {
        authorization: "Bearer user",
        "idempotency-key": U,
        "content-type": "application/json",
      },
      body: JSON.stringify(body),
    });
  assert.equal(
    (
      await router(
        req("/purchases/verify", {
          app_user_id: "22222222-2222-4222-8222-222222222222",
        }),
      )
    ).status,
    403,
  );
  assert.equal((await router(req("/purchases/verify", {}))).status, 200);
  assert.equal(
    (
      await router(
        req("/analysis/requests", { consent_version: "1", media_ids: [U] }),
      )
    ).status,
    202,
  );
  assert.equal(
    (
      await router(
        req("/analysis/requests", { consent_version: "1", media_ids: [U, U] }),
      )
    ).status,
    400,
  );
});
