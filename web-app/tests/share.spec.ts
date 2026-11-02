import { test, expect, request as playwright } from "@playwright/test";
import { installSession, mutationHeaders, origin, provider } from "./support/session";
import { newDocument } from "../src/lib/notebook";

test.beforeEach(async ({ request }) => { await request.post(`${provider}/__test__/reset`); });

async function createNotebook(context: Parameters<typeof installSession>[0], title: string) {
  const id = crypto.randomUUID();
  const document = newDocument(title);
  document.pages[0].text = "Secret lecture notes";
  document.pages[0].strokes.push({ id: crypto.randomUUID(), tool: "pen", geometry: "polyline", points: [{ x: 10, y: 10 }, { x: 60, y: 40 }, { x: 120, y: 30 }], color: "#112233", width: 3, opacity: 1 });
  const response = await context.request.post("/api/notebooks", { headers: mutationHeaders, data: { id, document, mutationId: crypto.randomUUID() } });
  expect(response.status()).toBe(201);
  return id;
}

test("owners create, view and revoke a read-only share link that anonymous visitors can open", async ({ context, request }) => {
  await installSession(context, request, "?user=invited");
  const id = await createNotebook(context, "Shared physics");
  expect((await (await context.request.get(`/api/v1/share/${id}`)).json()).shared).toBe(false);
  expect((await context.request.post(`/api/v1/share/${id}`, { data: {} })).status()).toBe(403); // CSRF: no Origin header.
  const created = await context.request.post(`/api/v1/share/${id}`, { headers: mutationHeaders, data: {} });
  expect(created.status()).toBe(200);
  const { url } = await created.json();
  expect(url).toMatch(new RegExp(`^${origin}/share/[A-Za-z0-9_-]{43}$`));
  // Creating again returns the same link instead of rotating it.
  expect((await (await context.request.post(`/api/v1/share/${id}`, { headers: mutationHeaders, data: {} })).json()).url).toBe(url);

  const anonymous = await playwright.newContext({ baseURL: origin });
  const page = await anonymous.get(url);
  expect(page.status()).toBe(200);
  const html = await page.text();
  expect(html).toContain("Shared physics");
  expect(html).toContain("Secret lecture notes");
  expect(html).toContain("M10 10Q60 40 90 35L120 30"); // Smoothed ink path.
  expect(html).toContain("noindex");
  expect((await anonymous.get(`/api/notebooks/${id}`)).status()).toBe(401); // A link grants no API access.

  expect((await (await context.request.delete(`/api/v1/share/${id}`, { headers: mutationHeaders, data: {} })).json()).shared).toBe(false);
  expect((await anonymous.get(url)).status()).toBe(404);
  await anonymous.dispose();
});

test("share links reject unknown tokens, other accounts, and deleted notebooks", async ({ context, request }) => {
  await installSession(context, request, "?user=invited");
  const id = await createNotebook(context, "Private until shared");
  const { url } = await (await context.request.post(`/api/v1/share/${id}`, { headers: mutationHeaders, data: {} })).json();
  const anonymous = await playwright.newContext({ baseURL: origin });
  expect((await anonymous.get(`/share/${"A".repeat(43)}`)).status()).toBe(404);
  expect((await anonymous.get("/share/short")).status()).toBe(404);

  await context.clearCookies();
  await installSession(context, request, "?user=admin");
  expect((await context.request.post(`/api/v1/share/${id}`, { headers: mutationHeaders, data: {} })).status()).toBe(404); // Not the owner.
  await context.request.delete(`/api/v1/share/${id}`, { headers: mutationHeaders, data: {} }); // Scoped to the caller's own links: a no-op here.
  expect((await anonymous.get(url)).status()).toBe(200); // Another account cannot revoke it.

  await context.clearCookies();
  await installSession(context, request, "?user=invited");
  expect((await context.request.delete(`/api/notebooks/${id}`, { headers: mutationHeaders, data: { revision: 1 } })).status()).toBe(200);
  expect((await anonymous.get(url)).status()).toBe(404); // Deleted notebooks stop being served.
  await anonymous.dispose();
});

test("the editor menu creates, copies and stops a share link", async ({ page, context, request }) => {
  await installSession(context, request, "?user=invited");
  const id = await createNotebook(context, "Menu sharing");
  await page.goto(`/notebooks/${id}`);
  await page.getByLabel("Notebook menu", { exact: true }).click();
  await page.getByRole("button", { name: "Share link" }).click();
  await page.getByRole("button", { name: "Create share link" }).click();
  await expect(page.getByLabel("Share link", { exact: true })).toHaveValue(new RegExp(`${origin}/share/`));
  await page.getByRole("button", { name: "Stop sharing" }).click();
  await expect(page.getByRole("button", { name: "Create share link" })).toBeVisible();
});
