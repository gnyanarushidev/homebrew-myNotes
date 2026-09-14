import { after, before, test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { PGlite } from "@electric-sql/pglite";

// Execute the actual migration in embedded PostgreSQL. Auth/PostgREST HTTP
// behavior is tested separately by Playwright's local provider.
const db = new PGlite();
const owner = "11111111-1111-4111-8111-111111111111";
const id = "22222222-2222-4222-8222-222222222222";
before(async () => {
  await db.exec(`
    create schema auth;
    create table auth.users (id uuid primary key);
    create role anon;
    create role authenticated;
    create role service_role bypassrls;
    insert into auth.users values ('${owner}');
  `);
  const migration = await readFile(new URL("../supabase/migrations/001_notebooks.sql", import.meta.url), "utf8");
  await db.exec(migration);
  await db.exec(migration);
});
after(async () => { await db.close(); });

test("migration stores documents and derives searchable library metadata", async () => {
  await db.exec("set role service_role");
  try {
    await db.query("insert into public.mynotes_notebooks (id, owner_id, document, mutation_id) values ($1, $2, $3, $1)", [id, owner, { schemaVersion: 1, title: "Mountain ideas", template: "grid", color: "cream", pages: [{ text: "A searchable thought" }, { text: "Second page" }] }]);
    const { rows } = await db.query("select title, template, color, page_count, revision from public.mynotes_notebooks where search_text ilike '%searchable%'");
    assert.deepEqual(rows, [{ title: "Mountain ideas", template: "grid", color: "cream", page_count: 2, revision: 1 }]);
    await assert.rejects(db.exec(`update public.mynotes_notebooks set revision = 0 where id = '${id}'`), { code: "23514" });
    await assert.rejects(db.exec(`update public.mynotes_notebooks set owner_id = '33333333-3333-4333-8333-333333333333' where id = '${id}'`), { code: "23503" });
  } finally { await db.exec("reset role"); }
});

test("anonymous and authenticated roles have no direct access; RLS also denies reads", async () => {
  for (const role of ["anon", "authenticated"]) {
    await db.exec(`set role ${role}`);
    try {
      await assert.rejects(db.exec("select * from public.mynotes_notebooks"), { code: "42501" });
      await assert.rejects(db.exec("delete from public.mynotes_notebooks"), { code: "42501" });
    } finally { await db.exec("reset role"); }
    // Verify the default-deny RLS policy independently of the table grants.
    await db.exec(`grant select on public.mynotes_notebooks to ${role}; set role ${role}`);
    try { assert.deepEqual((await db.query("select * from public.mynotes_notebooks")).rows, []); }
    finally { await db.exec(`reset role; revoke select on public.mynotes_notebooks from ${role}`); }
  }
});

test("revision predicates prevent stale writes and stale deletions", async () => {
  await db.exec("set role service_role");
  try {
    const update = "update public.mynotes_notebooks set revision = revision + 1 where id = $1 and owner_id = $2 and revision = 1 returning revision";
    assert.deepEqual((await db.query(update, [id, owner])).rows, [{ revision: 2 }]);
    assert.deepEqual((await db.query(update, [id, owner])).rows, []);
    assert.deepEqual((await db.query("delete from public.mynotes_notebooks where id = $1 and owner_id = $2 and revision = 1 returning id", [id, owner])).rows, []);
  } finally { await db.exec("reset role"); }
});
