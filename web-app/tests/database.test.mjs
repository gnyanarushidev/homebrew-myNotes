import { after, before, test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { createHash } from "node:crypto";
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
  await db.exec(await readFile(new URL("../supabase/migrations/002_cloud_storage.sql", import.meta.url), "utf8"));
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

async function cloudObject(key, user = owner) {
  const sha256 = createHash("sha256").update(key).digest("hex");
  await db.query("insert into cloud_objects(key,owner_id,sha256,bytes,stored_bytes,kind,version_id,created_at) values($1,$2,$3,100,50,'page','version',now()-interval '2 days')", [key, user, sha256]);
  return { key, sha256, bytes: 100, kind: "page" };
}
const cloudManifest = file => ({ version: 1, title: "Metadata notebook", template: "grid", color: "cream", pages: [{ id: "77777777-7777-4777-8777-777777777777", size: "letterPortrait", template: "blank", color: "white", inheritsStyle: true, content: file }] });
async function cloudCommit(notebook, manifest, revision, operation = crypto.randomUUID(), options = {}) {
  const conflictId = options.conflictId ?? crypto.randomUUID();
  const result = await db.query("select cloud_commit($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) result", [owner, notebook, operation, options.hash ?? operation, revision, manifest, options.deleted ?? false, options.keepBoth ?? false, conflictId, { ...manifest, title: "Conflict copy" }]);
  return result.rows[0].result;
}

test("cloud metadata commits are atomic and operation receipts survive newer revisions", async () => {
  const notebook = crypto.randomUUID(), operation = crypto.randomUUID();
  const manifest = cloudManifest(await cloudObject(`users/${owner}/test-a`));
  const first = await cloudCommit(notebook, manifest, 0, operation);
  const second = await cloudCommit(notebook, { ...manifest, title: "New title" }, 1);
  assert.equal(second.revision, 2); assert.ok(second.sequence > first.sequence);
  assert.deepEqual(await cloudCommit(notebook, manifest, 0, operation), { ...first, duplicate: true });
  await assert.rejects(cloudCommit(notebook, manifest, 0, operation, { hash: "different" }), /OPERATION_REUSED/);
  const row = (await db.query("select manifest, revision from cloud_notebooks where owner_id=$1 and id=$2", [owner, notebook])).rows[0];
  assert.equal(row.revision, 2); assert.equal(row.manifest.title, "New title");
  assert.equal(JSON.stringify(row.manifest).includes('"strokes"'), false);
});

test("stale writes preserve a conflict copy; deletions retain a tombstone", async () => {
  const notebook = crypto.randomUUID(), copy = crypto.randomUUID();
  const manifest = cloudManifest(await cloudObject(`users/${owner}/conflicts`));
  await cloudCommit(notebook, manifest, 0);
  await cloudCommit(notebook, { ...manifest, title: "Cloud version" }, 1);
  const receipt = await cloudCommit(notebook, manifest, 1, crypto.randomUUID(), { keepBoth: true, conflictId: copy });
  assert.equal(receipt.id, copy); assert.equal(receipt.conflict, true);
  assert.equal((await db.query("select manifest->>'title' title from cloud_notebooks where owner_id=$1 and id=$2", [owner, notebook])).rows[0].title, "Cloud version");
  await assert.rejects(cloudCommit(notebook, manifest, 1, crypto.randomUUID(), { deleted: true }), /REVISION_CONFLICT/);
  await cloudCommit(notebook, manifest, 2, crypto.randomUUID(), { deleted: true });
  const row = (await db.query("select deleted, manifest from cloud_notebooks where owner_id=$1 and id=$2", [owner, notebook])).rows[0];
  assert.equal(row.deleted, true); assert.deepEqual(row.manifest.pages, []);
  await assert.rejects(cloudCommit(notebook, manifest, 0), /REVISION_CONFLICT/);
});

test("cleanup preserves current, previous and conflict references and blocks republishing deleting objects", async () => {
  const notebook = crypto.randomUUID();
  const a = await cloudObject(`users/${owner}/retention-a`), b = await cloudObject(`users/${owner}/retention-b`), c = await cloudObject(`users/${owner}/retention-c`);
  await cloudCommit(notebook, cloudManifest(a), 0);
  await cloudCommit(notebook, cloudManifest(b), 1);
  await cloudCommit(notebook, cloudManifest(c), 2);
  await cloudCommit(notebook, { ...cloudManifest(c), title: "Metadata-only change" }, 3);
  const candidates = (await db.query("select * from cloud_cleanup_candidates($1)", [owner])).rows;
  assert.ok(candidates.some(file => file.key === a.key));
  assert.ok(!candidates.some(file => [b.key, c.key, `users/${owner}/conflicts`].includes(file.key)));
  await assert.rejects(cloudCommit(notebook, cloudManifest(a), 4), /OBJECT_UNAVAILABLE/);
  assert.equal((await db.query("select revision from cloud_notebooks where owner_id=$1 and id=$2", [owner, notebook])).rows[0].revision, 4);
});

test("cloud tables and RPCs deny browser roles, foreign objects and embedded drawing payloads", async () => {
  const other = crypto.randomUUID(); await db.query("insert into auth.users values($1)", [other]);
  const foreign = await cloudObject(`users/${other}/private`, other);
  await assert.rejects(cloudCommit(crypto.randomUUID(), cloudManifest(foreign), 0), /OBJECT_UNAVAILABLE/);
  const local = await cloudObject(`users/${owner}/invalid-payload`);
  const manifest = cloudManifest(local); manifest.pages[0].strokes = [{ points: [] }];
  await assert.rejects(cloudCommit(crypto.randomUUID(), manifest, 0), { code: "23514" });
  const interrupted = await cloudObject(`users/${owner}/interrupted-upload`);
  await db.query("update cloud_objects set state='uploading', version_id=null where key=$1", [interrupted.key]);
  await assert.rejects(cloudCommit(crypto.randomUUID(), cloudManifest(interrupted), 0), /OBJECT_UNAVAILABLE/);
  assert.ok((await db.query("select * from cloud_cleanup_candidates($1)", [owner])).rows.some(row => row.key === interrupted.key && row.state === "deleting"));
  for (const role of ["anon", "authenticated"]) {
    await db.exec(`set role ${role}`);
    try {
      await assert.rejects(db.exec("select * from cloud_notebooks"), { code: "42501" });
      await assert.rejects(db.query("select * from cloud_cleanup_candidates($1)", [owner]), { code: "42501" });
    } finally { await db.exec("reset role"); }
  }
});
