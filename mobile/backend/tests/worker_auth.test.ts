import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import { PGlite } from "@electric-sql/pglite";
import { pgcrypto } from "@electric-sql/pglite/contrib/pgcrypto";
import {
  authorizeWorker,
  authorizeHeartbeat,
} from "../functions/job-worker/authorize.ts";
import { createWorkerHandler } from "../functions/job-worker/handler.ts";
const db = new PGlite({ extensions: { pgcrypto } });
async function admin(sql: string, args: unknown[] = []) {
  await db.exec("reset role");
  return db.query(sql, args);
}
async function service(sql: string) {
  await db.exec(
    `set role service_role;select set_config('request.jwt.claims','{"role":"service_role"}',false)`,
  );
  return db.query<{ allowed: boolean }>(sql);
}
async function dispatch() {
  await db.exec("reset role");
  const id = (
    await db.query<{ id: number }>(
      "select app_private.cc_worker_dispatch(true)id",
    )
  ).rows[0].id;
  await db.query(
    "select set_config('test.worker_cap',(select substring(headers->>'Authorization'from 8)from app_private.test_http_calls where id=$1),false)",
    [id],
  );
  return id;
}
before(async () => {
  await db.exec(
    `create role anon;create role authenticated;create role service_role;create schema extensions;create extension pgcrypto with schema extensions;create schema auth;create function auth.jwt()returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;grant usage on schema auth to service_role;create schema app_private;grant usage on schema app_private to service_role;create schema vault;create table vault.test_secrets(name text primary key,decrypted_secret text);create view vault.decrypted_secrets as select * from vault.test_secrets;create function vault.create_secret(new_secret text,new_name text,new_description text)returns uuid language plpgsql as $$begin insert into vault.test_secrets values(new_name,new_secret);return gen_random_uuid();end$$;create table public.cc_jobs(id uuid default gen_random_uuid(),kind text default 'delete_account',attempt integer,status text,available_at timestamptz,expires_at timestamptz,lease_until timestamptz);`,
  );
  await db.exec(
    await readFile(new URL("../sql/worker_auth.sql", import.meta.url), "utf8"),
  );
  // Vault encryption and cron/net transport are provider-owned. These stubs test
  // access/nonce/HMAC/scheduling semantics using real PostgreSQL pgcrypto.
  await db.exec(
    `create schema net;create table app_private.test_http_calls(id bigint generated always as identity primary key,url text,headers jsonb,body jsonb,timeout integer);create function net.http_post(url text,headers jsonb,body jsonb,timeout_milliseconds integer)returns bigint language plpgsql as $$declare n bigint;begin insert into app_private.test_http_calls(url,headers,body,timeout)values(url,headers,body,timeout_milliseconds)returning id into n;return n;end$$;create schema cron;create table cron.job(jobid bigint generated always as identity primary key,jobname text unique,schedule text,command text,active boolean default true);create function cron.schedule(job_name text,schedule text,command text)returns bigint language plpgsql as $$declare n bigint;begin insert into cron.job(jobname,schedule,command)values(job_name,schedule,command)on conflict(jobname)do update set schedule=excluded.schedule,command=excluded.command returning jobid into n;return n;end$$;create function cron.alter_job(job_id bigint,active boolean default null)returns void language sql as $$update cron.job set active=coalesce(alter_job.active,job.active)where jobid=job_id$$;insert into cron.job(jobname,schedule,command)values('existing-marketing-job','0 * * * *','select 1');`,
  );
  const schedule = (
    await readFile(
      new URL("../sql/worker_schedule.sql", import.meta.url),
      "utf8",
    )
  ).replace(/^create extension.*;$/gm, "");
  await db.exec(schedule);
  await db.exec(
    await readFile(
      new URL("../sql/worker_health.sql", import.meta.url),
      "utf8",
    ),
  );
});
after(() => db.close());
test("scheduler is installed inactive and preserves existing jobs; no raw key in command/queue", async () => {
  const rows = (
    await admin("select jobname,active,command from cron.job order by jobid")
  ).rows as any[];
  assert.equal(rows[0].active, true);
  assert.equal(rows[1].jobname, "crispy-crust-mobile-job-worker-v1");
  assert.equal(rows[1].active, false);
  assert.equal(rows[1].command, "select app_private.cc_worker_dispatch();");
  assert.ok(!rows[1].command.includes("Bearer"));
  await dispatch();
  const result = (
    await admin(
      "select exists(select 1 from app_private.test_http_calls q join vault.decrypted_secrets s on q.headers::text like '%'||s.decrypted_secret||'%')leaked",
    )
  ).rows[0] as any;
  assert.equal(result.leaked, false);
});
test("only service-role RPC caller with matching JWT role can authorize", async () => {
  await dispatch();
  await db.exec("set role authenticated");
  await assert.rejects(
    db.query("select cc_worker_authorize(current_setting('test.worker_cap'))"),
    /permission denied/,
  );
  await assert.rejects(
    db.query("select * from app_private.worker_dispatches"),
    /permission denied/,
  );
  await db.exec(
    `reset role;set role service_role;select set_config('request.jwt.claims','{"role":"authenticated"}',false)`,
  );
  await assert.rejects(
    db.query("select cc_worker_authorize(current_setting('test.worker_cap'))"),
    /WORKER_SERVER_ROLE_REQUIRED/,
  );
});
test("valid HMAC capability is accepted once, then replay is rejected", async () => {
  await dispatch();
  assert.equal(
    (
      await service(
        "select cc_worker_authorize(current_setting('test.worker_cap'))allowed",
      )
    ).rows[0].allowed,
    true,
  );
  assert.equal(
    (
      await service(
        "select cc_worker_authorize(current_setting('test.worker_cap'))allowed",
      )
    ).rows[0].allowed,
    false,
  );
});
test("tampering and expiry reject without consuming a legitimate capability", async () => {
  await dispatch();
  await admin(
    "select set_config('test.worker_bad',left(current_setting('test.worker_cap'),-1)||case right(current_setting('test.worker_cap'),1)when '0'then '1'else '0'end,false)",
  );
  assert.equal(
    (
      await service(
        "select cc_worker_authorize(current_setting('test.worker_bad'))allowed",
      )
    ).rows[0].allowed,
    false,
  );
  assert.equal(
    (
      await service(
        "select cc_worker_authorize(current_setting('test.worker_cap'))allowed",
      )
    ).rows[0].allowed,
    true,
  );
  await dispatch();
  await admin(
    "update app_private.worker_dispatches set expires_at=now()-interval '1 second',issued_at=now()-interval '121 seconds'where used_at is null",
  );
  assert.equal(
    (
      await service(
        "select cc_worker_authorize(current_setting('test.worker_cap'))allowed",
      )
    ).rows[0].allowed,
    false,
  );
});
test("empty queues do not invoke network and clients cannot dispatch", async () => {
  assert.equal(
    ((await admin("select app_private.cc_worker_dispatch()id")).rows[0] as any)
      .id,
    null,
  );
  await db.exec("set role service_role");
  await assert.rejects(
    db.query("select app_private.cc_worker_dispatch(true)"),
    /permission denied/,
  );
  await assert.rejects(
    db.query("select app_private.worker_signature('anything')"),
    /permission denied/,
  );
});
test("Edge authorization fails closed and never calls Vault for malformed tokens", async () => {
  const token =
    "v1.1790000000.11111111-1111-4111-8111-111111111111." + "a".repeat(64);
  let calls = 0;
  const req = (value: string) =>
    new Request("https://backend.test/job-worker", {
      method: "POST",
      headers: { authorization: value },
    });
  assert.equal(
    await authorizeWorker(req("Bearer invalid"), "", async () => {
      calls++;
      return true;
    }),
    false,
  );
  assert.equal(calls, 0);
  assert.equal(
    await authorizeWorker(req("Bearer " + token), "", async () => {
      calls++;
      return true;
    }),
    true,
  );
  assert.equal(
    await authorizeWorker(req("Bearer " + token), "", async () => {
      throw new Error("network");
    }),
    false,
  );
  assert.equal(
    await authorizeWorker(
      req("Bearer explicit-test-secret"),
      "explicit-test-secret",
      async () => false,
    ),
    true,
  );
});
test("worker migration source and applied app versions are recorded faithfully", async () => {
  const files = await readdir(
    new URL("../supabase/migrations", import.meta.url),
  );
  assert.ok(files.includes("20261111151503_crispy_mobile_kernel_v1.sql"));
  assert.ok(
    files.includes("20261111151519_crispy_mobile_media_billing_v1.sql"),
  );
  assert.ok(
    !files.some(
      (x) => x.startsWith("20261111143554") || x.startsWith("20261111145945"),
    ),
  );
  const name = files.find((x) => x.endsWith("_worker_vault_dispatch_v1.sql"));
  assert.ok(name);
  assert.equal(
    await readFile(
      new URL("../supabase/migrations/" + name, import.meta.url),
      "utf8",
    ),
    (await readFile(
      new URL("../sql/worker_auth.sql", import.meta.url),
      "utf8",
    )) +
      "\n" +
      (await readFile(
        new URL("../sql/worker_schedule.sql", import.meta.url),
        "utf8",
      )),
  );
});

async function heartbeat() {
  await db.exec("reset role");
  const id = (
    await db.query<{ id: number }>("select app_private.cc_worker_heartbeat()id")
  ).rows[0].id;
  await db.query(
    "select set_config('test.health_cap',(select substring(headers->>'Authorization'from 8)from app_private.test_http_calls where id=$1),false)",
    [id],
  );
  return id;
}
test("heartbeat dispatch targets only health and cannot authorize or claim jobs", async () => {
  await admin(
    "insert into cc_jobs(kind,attempt,status,available_at,expires_at)values('delete_account',0,'queued',now(),now()+interval '1 day')",
  );
  const requestId = await heartbeat();
  const row = (
    await admin(
      "select url,body from app_private.test_http_calls where id=$1",
      [requestId],
    )
  ).rows[0] as any;
  assert.equal(
    row.url,
    "https://wpxeuwknbuxbtkkkmcsm.supabase.co/functions/v1/job-worker/health",
  );
  assert.deepEqual(row.body, { mode: "heartbeat" });
  assert.equal(
    (
      await service(
        "select cc_worker_authorize(current_setting('test.health_cap'))allowed",
      )
    ).rows[0].allowed,
    false,
  );
  await admin(
    "select set_config('test.promoted_health','v1.'||split_part(current_setting('test.health_cap'),'.',3)||'.'||split_part(current_setting('test.health_cap'),'.',4)||'.'||split_part(current_setting('test.health_cap'),'.',5),false)",
  );
  assert.equal(
    (
      await service(
        "select cc_worker_authorize(current_setting('test.promoted_health'))allowed",
      )
    ).rows[0].allowed,
    false,
  );
  assert.equal(
    (
      await service(
        "select cc_worker_authorize_health(current_setting('test.health_cap'))allowed",
      )
    ).rows[0].allowed,
    true,
  );
  assert.equal(
    (
      await service(
        "select cc_worker_authorize_health(current_setting('test.health_cap'))allowed",
      )
    ).rows[0].allowed,
    false,
  );
  const jobs = (await admin("select count(*)::integer n from cc_jobs"))
    .rows[0] as any;
  assert.equal(jobs.n, 1);
  const untouched = (await admin("select kind,status,attempt from cc_jobs"))
    .rows[0] as any;
  assert.deepEqual(untouched, {
    kind: "delete_account",
    status: "queued",
    attempt: 0,
  });
  await admin("delete from cc_jobs");
});
test("health RPC and dispatcher remain inaccessible to ordinary clients", async () => {
  await heartbeat();
  await db.exec("set role authenticated");
  await assert.rejects(
    db.query(
      "select cc_worker_authorize_health(current_setting('test.health_cap'))",
    ),
    /permission denied/,
  );
  await assert.rejects(
    db.query("select app_private.cc_worker_heartbeat()"),
    /permission denied/,
  );
  await db.exec(
    `reset role;set role service_role;select set_config('request.jwt.claims','{"role":"authenticated"}',false)`,
  );
  await assert.rejects(
    db.query(
      "select cc_worker_authorize_health(current_setting('test.health_cap'))",
    ),
    /WORKER_SERVER_ROLE_REQUIRED/,
  );
  const job = (
    await admin(
      "select active from cron.job where jobname='crispy-crust-mobile-job-worker-v1'",
    )
  ).rows[0] as any;
  assert.equal(job.active, false);
});
test("health handler returns before processing and ignores attempts to flip path/body/query mode", async () => {
  let claims = 0,
    deletions = 0,
    jobAuth = 0,
    healthAuth = 0;
  const handler = createWorkerHandler({
    authorizeJobs: async () => {
      jobAuth++;
      return false;
    },
    authorizeHeartbeat: async () => {
      healthAuth++;
      return true;
    },
    processJobs: async () => {
      claims++;
      deletions++;
      throw new Error("must not execute");
    },
  });
  const req = (path: string, body: string) =>
    new Request("https://backend.test/functions/v1/job-worker" + path, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body,
    });
  const result = await handler(
    req(
      "/health?mode=jobs",
      '{"mode":"jobs","claim":true,"delete_account":true}',
    ),
  );
  assert.equal(result.status, 200);
  assert.deepEqual(await result.json(), { ok: true, mode: "heartbeat" });
  assert.equal(claims, 0);
  assert.equal(deletions, 0);
  assert.equal(jobAuth, 0);
  assert.equal(healthAuth, 1);
  assert.equal((await handler(req("", '{"mode":"heartbeat"}'))).status, 401);
  assert.equal(claims, 0);
  assert.equal((await handler(req("/health/jobs", "{}"))).status, 404);
  assert.equal(claims, 0);
});
test("heartbeat token cannot become legacy processing authorization and fails closed", async () => {
  const token =
    "v2.heartbeat.1790000000.11111111-1111-4111-8111-111111111111." +
    "a".repeat(64);
  const req = new Request("https://backend.test/job-worker/health", {
    method: "POST",
    headers: { authorization: "Bearer " + token },
  });
  assert.equal(await authorizeWorker(req, token, async () => true), false);
  assert.equal(await authorizeHeartbeat(req, async () => true), true);
  assert.equal(
    await authorizeHeartbeat(req, async () => {
      throw new Error("network");
    }),
    false,
  );
});
test("read-only health migration exactly matches its reviewed source", async () => {
  const names = await readdir(
    new URL("../supabase/migrations", import.meta.url),
  );
  assert.ok(
    names.includes("20261111155139_crispy_mobile_worker_vault_dispatch_v1.sql"),
  );
  assert.ok(
    names.includes(
      "20261111155946_crispy_mobile_worker_readonly_health_v1.sql",
    ),
  );
  const name = names.find((x) => x.endsWith("_worker_readonly_health_v1.sql"));
  assert.ok(name);
  assert.equal(
    await readFile(
      new URL("../supabase/migrations/" + name, import.meta.url),
      "utf8",
    ),
    await readFile(
      new URL("../sql/worker_health.sql", import.meta.url),
      "utf8",
    ),
  );
});
