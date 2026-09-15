import { createHash } from "node:crypto";
import { test, expect, type APIRequestContext } from "@playwright/test";
import { installSession, mutationHeaders, provider } from "./support/session";
import { newDocument } from "../src/lib/notebook";
import type { CloudFile, CloudManifest, CloudRecord } from "../src/lib/cloud";

test.beforeEach(async ({ request }) => { await request.post(`${provider}/__test__/reset`); });
async function upload(request: APIRequestContext, authorization: string, operationId: string, text: string) {
  const bytes = Buffer.from(JSON.stringify({ version: 1, text, strokes: [] }));
  const prepared = await request.post("/api/v1/sync/uploads", { headers: { Authorization: authorization }, data: { operationId, files: [{ id: crypto.randomUUID(), sha256: createHash("sha256").update(bytes).digest("hex"), bytes: bytes.length, kind: "page" }] } });
  expect(prepared.status()).toBe(200);
  const ticket = (await prepared.json()).files[0];
  expect((await request.put(ticket.url, { headers: ticket.headers, data: bytes })).ok()).toBe(true);
  const file: CloudFile = { key: ticket.key, sha256: ticket.sha256, bytes: ticket.bytes, kind: "page" };
  return { file, ticket, bytes };
}
const manifest = (file: CloudFile): CloudManifest => ({ version: 1, title: "Native cloud", template: "grid", color: "white", pages: [{ id: crypto.randomUUID(), template: "grid", color: "white", size: "letterPortrait", inheritsStyle: true, content: file }] });

test("native bearer admission, signed page transfer, and metadata-only publication work together", async ({ request, context }) => {
  const session = await installSession(context, request, "?user=invited");
  const authorization = `Bearer ${session.access_token}`;
  expect((await request.get("/api/v1/account", { headers: { Authorization: authorization } })).status()).toBe(200);
  expect((await context.request.get("/api/v1/account", { headers: { Authorization: "Bearer forged" } })).status()).toBe(401);
  expect((await context.request.get("/api/v1/account", { headers: { "X-MyNotes-Account": crypto.randomUUID() } })).status()).toBe(403);
  const operationId = crypto.randomUUID(), id = crypto.randomUUID();
  const { file, ticket, bytes } = await upload(request, authorization, operationId, "This text belongs in B2, not a database drawing column.");
  const data = { id, operationId, baseRevision: 0, manifest: manifest(file), keepBoth: true };
  const commit = await request.post("/api/v1/sync/commit", { headers: { Authorization: authorization }, data });
  expect(commit.status()).toBe(200);
  const receipt = await commit.json(); expect(receipt).toMatchObject({ id, revision: 1, conflict: false });
  const response = await request.get(`/api/v1/sync/notebooks/${id}?downloads=1`, { headers: { Authorization: authorization } });
  const { record, urls } = await response.json();
  const saved = record.manifest.pages[0].content;
  expect(saved.key).toContain(`/objects/`); expect(saved.key).not.toBe(ticket.key);
  expect(JSON.stringify(record)).not.toContain("This text belongs"); expect(record.document).toBeUndefined();
  const downloaded = await request.get(urls[saved.key]);
  expect(await downloaded.json()).toMatchObject({ text: "This text belongs in B2, not a database drawing column." });
  // The staging URL cannot mutate the published object's independent key/version.
  await request.put(ticket.url, { headers: ticket.headers, data: Buffer.alloc(bytes.length, 32) });
  expect((await (await request.get(urls[saved.key])).json()).text).toContain("This text belongs");
  const retry = await request.post("/api/v1/sync/commit", { headers: { Authorization: authorization }, data });
  expect(await retry.json()).toMatchObject({ id, revision: 1, duplicate: true });
  const changes = await (await request.get("/api/v1/sync?cursor=0", { headers: { Authorization: authorization } })).json();
  expect(changes.records).toHaveLength(1); expect(changes.cursor).toBe(receipt.sequence);
});

test("unverified bytes and another account's file references cannot publish metadata", async ({ request, context }) => {
  const session = await installSession(context, request, "?user=invited");
  const authorization = `Bearer ${session.access_token}`, operationId = crypto.randomUUID();
  const { file, ticket, bytes } = await upload(request, authorization, operationId, "Original");
  await request.put(ticket.url, { headers: ticket.headers, data: Buffer.alloc(bytes.length, 32) });
  const input = { id: crypto.randomUUID(), operationId, baseRevision: 0, manifest: manifest(file) };
  expect((await request.post("/api/v1/sync/commit", { headers: { Authorization: authorization }, data: input })).status()).toBe(400);
  expect((await (await request.get("/api/v1/sync?cursor=0", { headers: { Authorization: authorization } })).json()).records).toHaveLength(0);
  expect((await request.post("/api/v1/sync/files", { headers: { Authorization: authorization }, data: { files: [{ ...file, key: `staging/${session.user.id}/../../private.json` }] } })).status()).toBe(400);
  await context.clearCookies(); const admin = await installSession(context, request);
  expect((await request.post("/api/v1/sync/commit", { headers: { Authorization: `Bearer ${admin.access_token}` }, data: { ...input, operationId: crypto.randomUUID() } })).status()).toBe(410);
  expect((await context.request.post("/api/v1/sync/uploads", { headers: { Origin: "https://untrusted.example" }, data: { operationId, files: [] } })).status()).toBe(403);
});

test("web receives desktop-style cloud changes on foreground without overwriting a dirty draft", async ({ page, request, context }) => {
  await installSession(context, request, "?user=invited");
  const id = crypto.randomUUID(), document = newDocument("Before native edit");
  await context.request.post("/api/notebooks", { headers: mutationHeaders, data: { id, document, mutationId: crypto.randomUUID() } });
  await page.goto(`/notebooks/${id}`); await expect(page.getByLabel("Notebook title")).toHaveValue("Before native edit");
  const remote: CloudRecord = await (await context.request.get(`/api/v1/sync/notebooks/${id}`)).json();
  await context.request.post("/api/v1/sync/commit", { headers: mutationHeaders, data: { id, operationId: crypto.randomUUID(), baseRevision: remote.revision, manifest: { ...remote.manifest, title: "Changed from another device" } } });
  await page.evaluate(() => window.dispatchEvent(new Event("focus")));
  await expect(page.getByLabel("Notebook title")).toHaveValue("Changed from another device");
  await page.route("**/api/v1/sync/commit", route => route.fulfill({ status: 503, contentType: "application/json", body: '{"error":"Save interrupted"}' }));
  await page.getByLabel("Notebook menu", { exact: true }).click();
  await page.getByLabel("Notebook title").fill("Pending local title");
  await page.evaluate(() => window.dispatchEvent(new Event("focus")));
  await expect(page.getByLabel("Notebook title")).toHaveValue("Pending local title");
});
