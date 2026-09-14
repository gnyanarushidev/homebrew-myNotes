import { test, expect } from "@playwright/test";
import { newDocument } from "../src/lib/notebook";
import { installSession, mutationHeaders, provider } from "./support/session";

test.beforeEach(async ({ request }) => { await request.post(`${provider}/__test__/reset`); });

test("notebook APIs enforce ownership, protected access metadata, CSRF, and document limits", async ({ context, request }) => {
  await installSession(context, request);
  const id = crypto.randomUUID();
  const document = newDocument("Admin notebook");
  const data = { id, document, mutationId: crypto.randomUUID() };
  const created = await context.request.post("/api/notebooks", { headers: mutationHeaders, data });
  expect(created.status()).toBe(201);
  expect(created.headers()["cache-control"]).toContain("no-store");
  await context.clearCookies();
  await installSession(context, request, "?user=invited");
  expect(await (await context.request.get("/api/notebooks")).json()).toEqual([]);
  expect((await context.request.get(`/api/notebooks/${id}`)).status()).toBe(404);
  expect((await context.request.put(`/api/notebooks/${id}`, { headers: mutationHeaders, data: { ...data, revision: 1 } })).status()).toBe(404);
  expect((await context.request.delete(`/api/notebooks/${id}`, { headers: mutationHeaders, data: { revision: 1 } })).status()).toBe(409);
  expect((await context.request.post("/api/admin/users", { headers: mutationHeaders, data: { email: "another@example.com" } })).status()).toBe(403);
  expect((await context.request.post("/api/notebooks", { headers: { Origin: "https://untrusted.example" }, data })).status()).toBe(403);
  expect((await context.request.post("/api/notebooks", { headers: mutationHeaders, data: { ...data, document: { ...document, schemaVersion: 2 } } })).status()).toBe(400);
  expect((await context.request.post("/api/notebooks", { headers: mutationHeaders, data: { ...data, document: { ...document, pages: [document.pages[0], document.pages[0]] } } })).status()).toBe(400);
  expect((await context.request.post("/api/notebooks", { headers: mutationHeaders, data: { ...data, padding: "x".repeat(3_000_000) } })).status()).toBe(413);
  await context.clearCookies();
  await installSession(context, request, "?user=member");
  expect((await context.request.get("/api/notebooks")).status()).toBe(403); // Editable user_metadata cannot grant access.
});

test("retries are idempotent, competing revisions conflict, and deletion checks the revision", async ({ context, request }) => {
  await installSession(context, request, "?user=invited");
  const id = crypto.randomUUID();
  const document = newDocument("Versioned notebook");
  const data = { id, document, mutationId: crypto.randomUUID() };
  const creations = await Promise.all([1, 2].map(() => context.request.post("/api/notebooks", { headers: mutationHeaders, data })));
  expect(creations.map(response => response.status()).sort()).toEqual([200, 201]);
  expect((await context.request.post("/api/notebooks", { headers: mutationHeaders, data })).status()).toBe(200);
  const mutations = ["First change", "Second change"].map(title => ({ ...data, document: { ...document, title }, revision: 1, mutationId: crypto.randomUUID() }));
  const responses = await Promise.all(mutations.map(data => context.request.put(`/api/notebooks/${id}`, { headers: mutationHeaders, data })));
  expect(responses.map(response => response.status()).sort()).toEqual([200, 409]);
  const winningIndex = responses.findIndex(response => response.status() === 200);
  const retry = await context.request.put(`/api/notebooks/${id}`, { headers: mutationHeaders, data: mutations[winningIndex] });
  expect(retry.status()).toBe(200);
  expect((await retry.json()).revision).toBe(2);
  expect((await context.request.delete(`/api/notebooks/${id}`, { headers: mutationHeaders, data: { revision: 1 } })).status()).toBe(409);
  expect((await context.request.delete(`/api/notebooks/${id}`, { headers: mutationHeaders, data: { revision: 2 } })).status()).toBe(200);
  expect((await context.request.get(`/api/notebooks/${id}`)).status()).toBe(404);
});
