import { PGlite } from "@electric-sql/pglite";
import { readFile } from "node:fs/promises";
const db = new PGlite();
await db.exec(
  `create role anon;create role authenticated;create role service_role;create schema auth;create table auth.users(id uuid primary key);create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;`,
);
let sql = await readFile(new URL("../sql/schema.sql", import.meta.url), "utf8");
try {
  await db.exec(sql);
  console.log("SQL valid");
} catch (e: any) {
  console.log(
    e.message,
    "position",
    e.position,
    "internal",
    e.internalPosition,
    "where",
    e.where,
  );
  console.log(sql.slice(Number(e.position) - 100, Number(e.position) + 100));
}
await db.close();
