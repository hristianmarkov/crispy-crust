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
    `create role anon;create role authenticated;create role service_role;create schema auth;create table auth.users(id uuid primary key);grant usage on schema auth to authenticated;create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;insert into auth.users values('${A}'),('${B}'),('${C}');`,
  );
  await db.exec(
    await readFile(new URL("../sql/schema.sql", import.meta.url), "utf8"),
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
    rpc(A, "cc_create_share", [ka, id(21), ["availability"], null]),
    /SHARE_FIELD_FORBIDDEN/,
  );
  const share = (await rpc(A, "cc_create_share", [ka, id(21), ["title"], null]))
    .result;
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
