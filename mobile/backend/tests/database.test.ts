import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { PGlite } from "@electric-sql/pglite";
const db = new PGlite();
const A = "11111111-1111-4111-8111-111111111111",
  B = "22222222-2222-4222-8222-222222222222",
  C = "33333333-3333-4333-8333-333333333333";
const device = "44444444-4444-4444-8444-444444444444";
const id = (n: number) =>
  `aaaaaaaa-aaaa-4aaa-8aaa-${String(n).padStart(12, "0")}`;
let ka: string, kb: string;
async function as(user: string, sql: string, params: any[] = []) {
  await db.exec(
    `set role authenticated; select set_config('request.jwt.claim.sub','${user}',false)`,
  );
  return db.query(sql, params);
}
async function rpc(user: string, name: string, args: any[] = []) {
  return (
    await as(
      user,
      `select public.${name}(${args.map((_, i) => `$${i + 1}`).join(",")}) as result`,
      args,
    )
  ).rows[0] as { result: any };
}
async function admin(sql: string, args: any[] = []) {
  await db.exec("reset role");
  return db.query(sql, args);
}
before(async () => {
  await db.exec(
    `create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key,last_sign_in_at timestamptz default now());grant usage on schema auth to authenticated;create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;insert into auth.users(id) values('${A}'),('${B}'),('${C}');`,
  );
  await db.exec(
    await readFile(new URL("../sql/schema.sql", import.meta.url), "utf8"),
  );
  await db.exec(
    `create schema storage;create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text,name text);alter table storage.objects enable row level security;grant usage on schema storage to authenticated;grant select on storage.objects to authenticated;`,
  );
  await db.exec(
    await readFile(new URL("../sql/storage.sql", import.meta.url), "utf8"),
  );
  await db.exec(
    `create function auth.jwt() returns jsonb language sql stable as $$select jsonb_build_object('aal',current_setting('request.jwt.claim.aal',true),'auth_time',current_setting('request.jwt.claim.auth_time',true))$$;`,
  );
  await db.exec(
    await readFile(new URL("../sql/features.sql", import.meta.url), "utf8"),
  );
  await db.exec(
    await readFile(
      new URL("../sql/media_billing.sql", import.meta.url),
      "utf8",
    ),
  );
  ka = (await rpc(A, "cc_bootstrap", ["Alice"])).result.kitchen_id;
  kb = (await rpc(B, "cc_bootstrap", ["Bob"])).result.kitchen_id;
  await rpc(C, "cc_bootstrap", ["Carol"]);
});
after(() => db.close());
test("bootstrap is idempotent; unauthenticated command denied", async () => {
  assert.equal((await rpc(A, "cc_bootstrap", ["Other"])).result.kitchen_id, ka);
  await db.exec(
    "reset role;set role anon;select set_config('request.jwt.claim.sub','',false)",
  );
  await assert.rejects(db.query("select cc_bootstrap()"), /permission denied/);
});
test("RLS hides other kitchens and generic DML is denied", async () => {
  let r = await as(A, "select id from cc_kitchens");
  assert.equal(r.rows.length, 1);
  assert.equal((r.rows[0] as any).id, ka);
  await assert.rejects(
    as(A, "update cc_kitchens set name='hacked'"),
    /permission denied/,
  );
  await assert.rejects(
    rpc(B, "cc_sync_pull", [ka, 0, 100]),
    /KITCHEN_ACCESS_REVOKED/,
  );
});
test("sync CAS and retry idempotency produce one durable change", async () => {
  const op = {
    operation_id: id(1),
    aggregate_id: id(2),
    base_revision: 0,
    type: "Upsert",
    kind: "starter",
    data: { name: "Mabel", hydration: 1 },
  };
  const r = (await rpc(A, "cc_sync_push", [ka, device, JSON.stringify([op])]))
    .result;
  assert.equal(r.accepted.length, 1);
  const retry = (
    await rpc(A, "cc_sync_push", [ka, device, JSON.stringify([op])])
  ).result;
  assert.deepEqual(retry.accepted, r.accepted);
  const pull = (await rpc(A, "cc_sync_pull", [ka, 0, 100])).result;
  assert.equal(pull.changes.length, 1);
  assert.equal(pull.changes[0].payload.data.name, "Mabel");
  const stale = { ...op, operation_id: id(3), data: { name: "Other" } };
  const conflict = (
    await rpc(A, "cc_sync_push", [ka, device, JSON.stringify([stale])])
  ).result;
  assert.equal(conflict.conflicts[0].code, "REVISION_CONFLICT");
});
test("forged tenant, privileged fields and changed idempotency key rejected", async () => {
  const tenant = (
    await rpc(B, "cc_sync_push", [
      kb,
      device,
      JSON.stringify([
        {
          operation_id: id(4),
          aggregate_id: id(2),
          base_revision: 1,
          type: "Upsert",
          kind: "starter",
          data: { name: "stolen" },
        },
      ]),
    ])
  ).result;
  assert.equal(tenant.conflicts[0].code, "CROSS_KITCHEN_ENTITY");
  const priv = (
    await rpc(A, "cc_sync_push", [
      ka,
      device,
      JSON.stringify([
        {
          operation_id: id(5),
          aggregate_id: id(6),
          base_revision: 0,
          type: "Upsert",
          kind: "starter",
          data: { approved: true },
        },
      ]),
    ])
  ).result;
  assert.equal(priv.conflicts[0].code, "PRIVILEGED_FIELD");
  const changed = (
    await rpc(A, "cc_sync_push", [
      ka,
      device,
      JSON.stringify([
        {
          operation_id: id(1),
          aggregate_id: id(2),
          base_revision: 0,
          type: "Upsert",
          kind: "starter",
          data: { name: "changed" },
        },
      ]),
    ])
  ).result;
  assert.equal(changed.conflicts[0].code, "IDEMPOTENCY_KEY_MISMATCH");
});
test("append-only actual history deduplicates physical completion and tombstones win", async () => {
  const create = {
    operation_id: id(10),
    aggregate_id: id(11),
    base_revision: 0,
    type: "Upsert",
    kind: "bake",
    data: { title: "Country loaf" },
  };
  await rpc(A, "cc_sync_push", [ka, device, JSON.stringify([create])]);
  let event = {
    operation_id: id(12),
    aggregate_id: id(11),
    base_revision: 1,
    type: "StepCompleted",
    payload: { step_id: "fold-1" },
  };
  assert.equal(
    (await rpc(A, "cc_sync_push", [ka, device, JSON.stringify([event])])).result
      .accepted.length,
    1,
  );
  let duplicate = { ...event, operation_id: id(13), base_revision: 2 };
  assert.equal(
    (await rpc(A, "cc_sync_push", [ka, device, JSON.stringify([duplicate])]))
      .result.conflicts[0].code,
    "DUPLICATE_PHYSICAL_ACTION_REVIEW",
  );
  await rpc(A, "cc_sync_push", [
    ka,
    device,
    JSON.stringify([
      {
        operation_id: id(14),
        aggregate_id: id(11),
        base_revision: 2,
        type: "Delete",
      },
    ]),
  ]);
  assert.equal(
    (
      await rpc(A, "cc_sync_push", [
        ka,
        device,
        JSON.stringify([{ ...create, operation_id: id(15), base_revision: 3 }]),
      ])
    ).result.conflicts[0].code,
    "TOMBSTONE_WINS",
  );
});
test("single-use hashed invitations; viewer read-only; revocation immediate", async () => {
  const inv = (await rpc(A, "cc_create_invite", [ka, "viewer", 3600])).result;
  assert.equal(
    (await rpc(B, "cc_redeem_invite", [inv.token])).result.role,
    "viewer",
  );
  await assert.rejects(
    rpc(C, "cc_redeem_invite", [inv.token]),
    /INVITE_INVALID/,
  );
  assert.ok(
    (await rpc(B, "cc_sync_pull", [ka, 0, 100])).result.changes.length > 0,
  );
  await assert.rejects(
    rpc(B, "cc_sync_push", [ka, device, "[]"]),
    /KITCHEN_ACCESS_REVOKED/,
  );
  await rpc(A, "cc_revoke_member", [ka, B]);
  await assert.rejects(
    rpc(B, "cc_sync_pull", [ka, 0, 100]),
    /KITCHEN_ACCESS_REVOKED/,
  );
});
test("share sanitization excludes private data; revocation invalidates access", async () => {
  await rpc(A, "cc_sync_push", [
    ka,
    device,
    JSON.stringify([
      {
        operation_id: id(20),
        aggregate_id: id(21),
        base_revision: 0,
        type: "Upsert",
        kind: "recipe",
        data: { title: "Bread", notes: "private", availability: "secret" },
      },
    ]),
  ]);
  await assert.rejects(
    rpc(A, "cc_create_share", [ka, id(21), ["availability"], null, 1]),
    /SHARE_FIELD_FORBIDDEN/,
  );
  const share = (
    await rpc(A, "cc_create_share", [ka, id(21), ["title"], null, 1])
  ).result;
  assert.deepEqual((await rpc(B, "cc_read_share", [share.token])).result.data, {
    title: "Bread",
  });
  await rpc(A, "cc_revoke_share", [share.share_id]);
  await assert.rejects(rpc(B, "cc_read_share", [share.token]), /SHARE_INVALID/);
});
test("coach jobs require independent consent and deduplicate quota", async () => {
  await assert.rejects(
    rpc(A, "cc_enqueue_job", [
      id(30),
      "coach",
      JSON.stringify({ consent_version: "1", question: "Help" }),
      null,
    ]),
    /CONSENT_REQUIRED/,
  );
  await rpc(A, "cc_grant_consent", ["coach", "1", true]);
  const j = (
    await rpc(A, "cc_enqueue_job", [
      id(30),
      "coach",
      JSON.stringify({ consent_version: "1", question: "Help" }),
      null,
    ])
  ).result;
  assert.equal(j.status, "queued");
  assert.equal(
    (
      await rpc(A, "cc_enqueue_job", [
        id(30),
        "coach",
        JSON.stringify({ consent_version: "1", question: "Help" }),
        null,
      ])
    ).result.job_id,
    j.job_id,
  );
});
test("plan CAS atomically replaces reminders and excludes conflicting oven reservation", async () => {
  for (const n of [40, 41])
    await rpc(A, "cc_sync_push", [
      ka,
      device,
      JSON.stringify([
        {
          operation_id: id(n + 100),
          aggregate_id: id(n),
          base_revision: 0,
          type: "Upsert",
          kind: "bake",
          data: { title: "Loaf" },
        },
      ]),
    ]);
  const snapshot = {
    engine_version: "1",
    tasks: [
      {
        step_id: "bake",
        start_at: "2026-12-01T10:00:00Z",
        finish_at: "2026-12-01T11:00:00Z",
      },
    ],
    reservations: [
      {
        resource_id: "oven",
        slot: 1,
        start_at: "2026-12-01T10:00:00Z",
        finish_at: "2026-12-01T11:00:00Z",
      },
    ],
  };
  let r = (
    await rpc(A, "cc_accept_plan", [
      ka,
      id(40),
      id(42),
      1,
      JSON.stringify(snapshot),
    ])
  ).result;
  assert.equal(r.bake_revision, 2);
  assert.equal(
    (
      await rpc(A, "cc_accept_plan", [
        ka,
        id(40),
        id(42),
        1,
        JSON.stringify(snapshot),
      ])
    ).result.schedule_id,
    r.schedule_id,
  );
  await assert.rejects(
    rpc(A, "cc_accept_plan", [ka, id(41), id(43), 1, JSON.stringify(snapshot)]),
    /RESOURCE_CAPACITY_CONFLICT/,
  );
  await assert.rejects(
    rpc(A, "cc_accept_plan", [ka, id(40), id(44), 1, JSON.stringify(snapshot)]),
    /REVISION_CONFLICT/,
  );
  const later = JSON.parse(JSON.stringify(snapshot));
  later.tasks[0].start_at = later.reservations[0].start_at =
    "2026-12-01T11:30:00Z";
  later.tasks[0].finish_at = later.reservations[0].finish_at =
    "2026-12-01T12:30:00Z";
  await rpc(A, "cc_accept_plan", [
    ka,
    id(40),
    id(45),
    2,
    JSON.stringify(later),
  ]);
  assert.equal(
    (
      await as(
        A,
        "select * from cc_reminders where aggregate_id=$1 and status='pending'",
        [id(40)],
      )
    ).rows.length,
    1,
  );
});
test("deletion marker revokes stale JWT commands and private access", async () => {
  const r = (await rpc(C, "cc_request_delete")).result;
  assert.equal(r.access_revoked, true);
  await assert.rejects(rpc(C, "cc_bootstrap", [null]), /AUTH_REQUIRED/);
  assert.equal((await as(C, "select * from cc_kitchens")).rows.length, 0);
});

test("public RPCs are invokers; private command and helper ACLs deny escalation", async () => {
  const r = await admin(
    "select proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and proname like 'cc_%' and prosecdef",
  );
  assert.equal(r.rows.length, 0);
  await assert.rejects(
    as(A, "select app_private.change($1,$2,'bake',99,'upsert','{}')", [
      ka,
      id(40),
    ]),
    /permission denied/,
  );
  await assert.rejects(as(A, "select cc_worker_claim(1)"), /permission denied/);
});
test("worker role leases once and rejects stale completion token", async () => {
  await db.exec("reset role;set role service_role");
  const jobs = (
    await db.query<{ result: any }>("select cc_worker_claim(20) result")
  ).rows[0].result;
  assert.ok(jobs.length > 0);
  const job = jobs[0];
  assert.equal(
    (
      await db.query<{ result: boolean }>(
        "select cc_worker_finish($1,$2,$3,null,false) result",
        [job.id, UndefUuid(), JSON.stringify({ answer: "x" })],
      )
    ).rows[0].result,
    false,
  );
  assert.equal(
    (
      await db.query<{ result: boolean }>(
        "select cc_worker_finish($1,$2,$3,null,false) result",
        [job.id, job.lease_token, JSON.stringify({ answer: "x" })],
      )
    ).rows[0].result,
    true,
  );
  assert.equal(
    (
      await db.query<{ result: boolean }>(
        "select cc_worker_finish($1,$2,$3,null,false) result",
        [job.id, job.lease_token, JSON.stringify({ answer: "x" })],
      )
    ).rows[0].result,
    false,
  );
});
function UndefUuid() {
  return "55555555-5555-4555-8555-555555555555";
}
test("storage policy checks asset membership and verified state, not path prefix", async () => {
  await admin(
    "insert into cc_media(id,kitchen_id,owner_id,object_key,sha256,mime_type,bytes,status,verified_at)values($1,$2,$3,'private/a.jpg',$4,'image/jpeg',100,'uploaded',now()),($5,$2,$3,'private/pending.jpg',$4,'image/jpeg',100,'pending',null)",
    [id(80), ka, A, "a".repeat(64), id(81)],
  );
  await admin(
    "insert into storage.objects(bucket_id,name)values('kitchen-media','private/a.jpg'),('kitchen-media','private/pending.jpg'),('kitchen-media','forged.jpg')",
  );
  assert.equal((await as(A, "select * from storage.objects")).rows.length, 1);
  assert.equal((await as(B, "select * from storage.objects")).rows.length, 0);
});
test("plan cannot mint extra resource slots or overlap own oven tasks", async () => {
  const base = {
    engine_version: "1",
    tasks: [],
    reservations: [
      {
        resource_id: "oven",
        slot: 2,
        start_at: "2026-12-02T10:00:00Z",
        finish_at: "2026-12-02T11:00:00Z",
      },
    ],
  };
  await assert.rejects(
    rpc(A, "cc_accept_plan", [ka, id(41), id(90), 1, JSON.stringify(base)]),
    /RESOURCE_CAPACITY_CONFLICT/,
  );
  base.reservations[0].slot = 1;
  base.reservations.push({ ...base.reservations[0] });
  await assert.rejects(
    rpc(A, "cc_accept_plan", [ka, id(41), id(91), 1, JSON.stringify(base)]),
    /RESOURCE_CAPACITY_CONFLICT/,
  );
});

test("publication requires moderation; staff requires role and MFA; block removes feed", async () => {
  const share = (
    await rpc(A, "cc_create_share", [ka, id(21), ["title"], null, 1])
  ).result;
  const post = (
    await rpc(A, "cc_publish_post", [share.share_id, "My loaf", id(200)])
  ).result;
  assert.equal(post.status, "pending");
  assert.equal(
    (await as(B, "select * from cc_posts where id=$1", [post.post_id])).rows
      .length,
    0,
  );
  await assert.rejects(
    rpc(B, "cc_moderate", ["post", post.post_id, "publish", "Reviewed"]),
    /STAFF_MFA_REQUIRED/,
  );
  await admin(
    "insert into app_private.staff_roles(user_id,role)values($1,$2)",
    [A, "moderator"],
  );
  await db.exec("select set_config('request.jwt.claim.aal','aal1',false)");
  await assert.rejects(
    rpc(A, "cc_moderate", ["post", post.post_id, "publish", "Reviewed"]),
    /STAFF_MFA_REQUIRED/,
  );
  await db.exec("select set_config('request.jwt.claim.aal','aal2',false)");
  assert.equal(
    (await rpc(A, "cc_moderate", ["post", post.post_id, "publish", "Reviewed"]))
      .result.status,
    "published",
  );
  assert.equal(
    (await as(B, "select * from cc_posts where id=$1", [post.post_id])).rows
      .length,
    1,
  );
  const comment = (
    await rpc(B, "cc_comment", [post.post_id, "Useful formula", id(201)])
  ).result;
  assert.equal(comment.status, "pending");
  await rpc(A, "cc_moderate", [
    "comment",
    comment.comment_id,
    "publish",
    "Useful",
  ]);
  assert.equal(
    (await as(A, "select * from cc_comments where id=$1", [comment.comment_id]))
      .rows.length,
    1,
  );
  await rpc(B, "cc_follow", [A, true]);
  assert.equal(
    (await as(B, "select * from cc_creator_follows")).rows.length,
    1,
  );
  await rpc(B, "cc_block", [A]);
  assert.equal(
    (await as(B, "select * from cc_posts where id=$1", [post.post_id])).rows
      .length,
    0,
  );
  await assert.rejects(
    rpc(B, "cc_comment", [post.post_id, "Blocked", id(202)]),
    /POST_NOT_FOUND/,
  );
});
test("share preview revision cannot publish changed values", async () => {
  await assert.rejects(
    rpc(A, "cc_create_share", [ka, id(21), ["title"], null, 99]),
    /REVISION_CONFLICT/,
  );
});
test("shared owner transfer checks recent auth and active target; permissions follow DB state", async () => {
  const k = (await rpc(A, "cc_create_kitchen", ["household", "Shared"])).result
    .kitchen_id;
  const invitation = (await rpc(A, "cc_create_invite", [k, "editor", 3600]))
    .result;
  await rpc(B, "cc_redeem_invite", [invitation.token]);
  await rpc(A, "cc_set_role", [k, B, "viewer"]);
  await assert.rejects(
    rpc(B, "cc_sync_push", [k, device, "[]"]),
    /KITCHEN_ACCESS_REVOKED/,
  );
  await admin(
    "update auth.users set last_sign_in_at=now()-interval '1 hour'where id=$1",
    [A],
  );
  await assert.rejects(rpc(A, "cc_transfer_owner", [k, B]), /REAUTH_REQUIRED/);
  await admin("update auth.users set last_sign_in_at=now()where id=$1", [A]);
  assert.equal((await rpc(A, "cc_transfer_owner", [k, B])).result.owner_id, B);
  await assert.rejects(rpc(A, "cc_transfer_owner", [k, A]), /OWNER_REQUIRED/);
  assert.equal(
    (await rpc(B, "cc_set_role", [k, A, "editor"])).result.role,
    "editor",
  );
});
test("deletion worker scrubs private state and retains only inaccessible identity tombstone", async () => {
  const job = (
    await admin(
      "select id from cc_jobs where user_id=$1 and kind='delete_account'",
      [C],
    )
  ).rows[0] as { id: string };
  await admin("update cc_jobs set status='running'where id=$1", [job.id]);
  await db.exec("set role service_role");
  const result = (
    await db.query<{ result: any }>(
      "select cc_worker_delete_data($1,$2)result",
      [C, job.id],
    )
  ).rows[0].result;
  assert.equal(result.purged, true);
  const profile = (
    await admin(
      "select display_name,account_state from cc_profiles where id=$1",
      [C],
    )
  ).rows[0] as any;
  assert.equal(profile.display_name, null);
  assert.equal(profile.account_state, "deleted");
  assert.equal((await as(C, "select * from cc_aggregates")).rows.length, 0);
});
test("record validation rejects impossible values and cross-tenant parent IDs", async () => {
  const invalid = (data: any) =>
    rpc(A, "cc_sync_push", [
      ka,
      device,
      JSON.stringify([
        {
          operation_id: crypto.randomUUID(),
          aggregate_id: crypto.randomUUID(),
          base_revision: 0,
          type: "Upsert",
          kind: "starter",
          data,
        },
      ]),
    ]);
  assert.equal(
    (await invalid({ name: "Bad", hydration: -10 })).result.conflicts[0].code,
    "INVALID_NUMERIC_FIELD",
  );
  assert.equal(
    (await invalid({ name: "Bad", kitchenValidated: true })).result.conflicts[0]
      .code,
    "REVIEW_AUTHORITY_REQUIRED",
  );
  const missing = (
    await rpc(A, "cc_sync_push", [
      ka,
      device,
      JSON.stringify([
        {
          operation_id: id(300),
          aggregate_id: id(301),
          base_revision: 0,
          type: "Upsert",
          kind: "feed",
          data: { starterId: id(999), flour: 40, water: 40, seed: 20 },
        },
      ]),
    ])
  ).result;
  assert.equal(missing.conflicts[0].code, "PARENT_NOT_IN_KITCHEN");
});
test("checked-in migration exactly matches verified source files", async () => {
  const { readdir } = await import("node:fs/promises");
  const files = await readdir(
    new URL("../supabase/migrations", import.meta.url),
  );
  const migration = files.find((x) => x.endsWith("_app_kernel.sql"));
  assert.ok(migration);
  const sources = await Promise.all(
    ["schema.sql", "features.sql", "storage.sql"].map((x) =>
      readFile(new URL("../sql/" + x, import.meta.url), "utf8"),
    ),
  );
  assert.equal(
    await readFile(
      new URL("../supabase/migrations/" + migration, import.meta.url),
      "utf8",
    ),
    sources.join("\n"),
  );
});

test("media preparation is tenant-scoped and idempotent; only verified objects become readable", async () => {
  const prepared = (
    await rpc(A, "cc_media_prepare", [
      ka,
      id(2),
      id(400),
      "b".repeat(64),
      100,
      "image/png",
      1,
      1,
    ])
  ).result;
  assert.equal(prepared.status, "pending");
  assert.equal(
    (
      await rpc(A, "cc_media_prepare", [
        ka,
        id(2),
        id(400),
        "b".repeat(64),
        100,
        "image/png",
        1,
        1,
      ])
    ).result.asset_id,
    prepared.asset_id,
  );
  await assert.rejects(
    rpc(B, "cc_media_for_verify", [prepared.asset_id]),
    /MEDIA_NOT_FOUND/,
  );
  await assert.rejects(
    rpc(A, "cc_media_for_read", [prepared.asset_id]),
    /MEDIA_NOT_FOUND/,
  );
  await assert.rejects(
    rpc(A, "cc_worker_media_status", [
      prepared.asset_id,
      "b".repeat(64),
      "uploaded",
    ]),
    /permission denied/,
  );
  await db.exec("reset role;set role service_role");
  assert.equal(
    (
      await db.query<{ result: boolean }>(
        "select cc_worker_media_status($1,$2,$3)result",
        [prepared.asset_id, "b".repeat(64), "uploaded"],
      )
    ).rows[0].result,
    true,
  );
  assert.equal(
    (await rpc(A, "cc_media_for_read", [prepared.asset_id])).result.id,
    prepared.asset_id,
  );
});
test("billing receipts deduplicate, reject hash changes and ignore stale snapshots", async () => {
  await db.exec("reset role;set role service_role");
  const now = new Date().toISOString();
  const rows = [
    { key: "pro", state: "active", valid_until: "2027-01-01T00:00:00Z" },
  ];
  let r = await db.query<{ result: any }>(
    "select cc_worker_entitlements($1,$2,$3,$4,$5)result",
    [A, "event-1", "a".repeat(64), now, JSON.stringify(rows)],
  );
  assert.equal(r.rows[0].result.applied, true);
  r = await db.query<{ result: any }>(
    "select cc_worker_entitlements($1,$2,$3,$4,$5)result",
    [A, "event-1", "a".repeat(64), now, JSON.stringify(rows)],
  );
  assert.equal(r.rows[0].result.duplicate, true);
  await assert.rejects(
    db.query("select cc_worker_entitlements($1,$2,$3,$4,$5)", [
      A,
      "event-1",
      "b".repeat(64),
      now,
      "[]",
    ]),
    /WEBHOOK_IDENTITY_MISMATCH/,
  );
  const stale = await db.query<{ result: any }>(
    "select cc_worker_entitlements($1,$2,$3,$4,$5)result",
    [A, "event-old", "c".repeat(64), "2020-01-01T00:00:00Z", "[]"],
  );
  assert.equal(stale.rows[0].result.applied, false);
  assert.equal(
    (
      (
        await as(
          A,
          "select state from cc_entitlements where entitlement_key='pro'",
        )
      ).rows[0] as any
    ).state,
    "active",
  );
  await assert.rejects(
    as(
      B,
      "insert into cc_entitlements(user_id,entitlement_key,state,provider)values($1,'pro','active','fake')",
      [B],
    ),
    /permission denied/,
  );
});
test("media and billing migration matches source", async () => {
  const { readdir } = await import("node:fs/promises");
  const name = (
    await readdir(new URL("../supabase/migrations", import.meta.url))
  ).find((x) => x.endsWith("_media_billing.sql"));
  assert.ok(name);
  assert.equal(
    await readFile(
      new URL("../supabase/migrations/" + name, import.meta.url),
      "utf8",
    ),
    await readFile(
      new URL("../sql/media_billing.sql", import.meta.url),
      "utf8",
    ),
  );
});
