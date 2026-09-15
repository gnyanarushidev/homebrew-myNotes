import { test, expect } from "@playwright/test";
import { installSession, mutationHeaders, provider } from "./support/session";
import { newDocument, type NotebookRecord } from "../src/lib/notebook";

test.beforeEach(async ({ request }) => { await request.post(`${provider}/__test__/reset`); });

test("public routes render and the private workspace requires sign-in", async ({ page, request }) => {
  const health = await request.get("/api/v1/health");
  expect(health.status()).toBe(200);
  expect(health.headers()["cache-control"]).toBe("no-store");
  expect(await health.json()).toMatchObject({ status: "ok", service: "mynotes-api" });
  for (const path of ["/", "/login", "/invite", "/forgot-password", "/setup"]) expect((await request.get(path)).status(), path).toBe(200);
  await page.goto("/");
  await expect(page.getByRole("heading", { level: 1 })).toContainText("big ideas");
  await page.getByRole("link", { name: "Explore the workspace", exact: true }).click();
  await expect(page).toHaveURL(/\/login\?reason=anonymous$/);
  expect((await request.get("/api/notebooks")).status()).toBe(401);
  const missing = await page.goto("/missing-page");
  expect(missing?.status()).toBe(404);
  await expect(page.getByRole("link", { name: "Back to notebooks" })).toBeVisible();
});

test("notebooks persist text, pages, paper overrides, and JSON backups across reloads", async ({ page, request, context }) => {
  await installSession(context, request, "?user=invited");
  await page.goto("/notebooks");
  await expect(page.getByRole("heading", { name: "Start with a blank page" })).toBeVisible();
  await page.getByRole("button", { name: "New notebook", exact: true }).click();
  await page.getByLabel("Notebook name").fill("Weekend sketches");
  await page.getByRole("dialog").getByLabel("Paper template").selectOption("dots");
  await page.getByRole("button", { name: "Create notebook", exact: true }).click();
  await expect(page.getByLabel("Notebook title")).toHaveValue("Weekend sketches");
  await page.getByRole("button", { name: "Text", exact: true }).click();
  await page.getByLabel("Page 1 text").fill("A searchable thought about mountains.");
  await page.getByLabel("Notebook menu", { exact: true }).click();
  await page.getByRole("button", { name: "Add page", exact: true }).last().click();
  await expect(page.getByRole("status").filter({ hasText: "Page 2 of 2" })).toHaveText("Page 2 of 2");
  await page.getByLabel("Notebook menu", { exact: true }).click();
  await page.getByRole("button", { name: "Paper & page" }).click();
  await page.getByLabel("Use notebook style").uncheck();
  await page.getByRole("main").getByLabel("Paper template").selectOption("grid");
  await page.getByRole("main").getByLabel("Paper color").selectOption("cream");
  await page.getByRole("main").getByLabel("Page size").selectOption("a4Portrait");
  await page.getByRole("dialog", { name: "Paper & page" }).getByRole("button", { name: "Close dialog" }).click();
  await expect(page.getByRole("status").filter({ hasText: "Saved to cloud" })).toBeVisible();
  const notebookUrl = page.url();
  await page.reload();
  await page.getByLabel("Notebook menu", { exact: true }).click();
  await page.getByRole("button", { name: "Paper & page" }).click();
  await expect(page.getByRole("main").getByLabel("Paper template")).toHaveValue("dots");
  await page.getByRole("dialog", { name: "Paper & page" }).getByRole("button", { name: "Close dialog" }).click();
  await page.getByRole("button", { name: "Text", exact: true }).click();
  await expect(page.getByLabel("Page 1 text")).toHaveValue("A searchable thought about mountains.");
  await page.getByLabel("Current page").selectOption({ value: "1" });
  await page.getByLabel("Notebook menu", { exact: true }).click();
  await page.getByRole("button", { name: "Paper & page" }).click();
  await expect(page.getByRole("main").getByLabel("Paper template")).toHaveValue("grid");
  await expect(page.getByRole("main").getByLabel("Paper color")).toHaveValue("cream");
  await expect(page.getByRole("main").getByLabel("Page size")).toHaveValue("a4Portrait");
  await page.getByRole("dialog", { name: "Paper & page" }).getByRole("button", { name: "Close dialog" }).click();
  const downloadPromise = page.waitForEvent("download");
  await page.getByLabel("Notebook menu", { exact: true }).click();
  await page.getByRole("button", { name: "Export JSON" }).click();
  const download = await downloadPromise;
  const stream = await download.createReadStream();
  const chunks = [];
  for await (const chunk of stream!) chunks.push(chunk);
  const backup = Buffer.concat(chunks);
  expect(JSON.parse(backup.toString())).toMatchObject({ schemaVersion: 1, title: "Weekend sketches", pages: [{ text: "A searchable thought about mountains." }, { size: "a4Portrait" }] });
  await page.getByLabel("Account menu", { exact: true }).click();
  await page.getByRole("navigation", { name: "Workspace navigation" }).getByRole("link", { name: "Notebooks", exact: true }).click();
  await page.getByRole("searchbox", { name: "Search notebooks" }).fill("Weekend");
  await expect(page.getByRole("link", { name: /Weekend sketches/ })).toBeVisible();
  await page.getByRole("searchbox", { name: "Search notebooks" }).fill("missing");
  await expect(page.getByRole("heading", { name: "No matching notebooks" })).toBeVisible();
  await page.getByRole("searchbox", { name: "Search notebooks" }).clear();
  await page.locator('input[type="file"]').setInputFiles({ name: "backup.json", mimeType: "application/json", buffer: backup });
  await expect(page).not.toHaveURL(/\/notebooks$/);
  expect(page.url()).not.toBe(notebookUrl);
  await page.getByRole("button", { name: "Text", exact: true }).click();
  await expect(page.getByLabel("Page 1 text")).toHaveValue("A searchable thought about mountains.");
});

test("an interrupted save recovers locally and preserves a newer cloud version as a conflict copy", async ({ page, request, context }) => {
  await installSession(context, request, "?user=invited");
  const id = crypto.randomUUID();
  const document = newDocument("Recovery notebook");
  const record: NotebookRecord = await (await context.request.post("/api/notebooks", { headers: mutationHeaders, data: { id, document, mutationId: crypto.randomUUID() } })).json();
  await page.goto(`/notebooks/${id}`);
  await page.getByRole("button", { name: "Text", exact: true }).click();
  await expect(page.getByLabel("Page 1 text")).toBeVisible();
  await page.route("**/api/v1/sync/commit", route => route.fulfill({ status: 503, contentType: "application/json", body: JSON.stringify({ error: "Simulated interrupted save" }) }));
  await page.getByLabel("Page 1 text").fill("Keep this local work.");
  await expect(page.getByRole("alert").filter({ hasText: "Simulated interrupted save" })).toBeVisible();
  const cloud = { ...document, title: "Newer cloud version", pages: document.pages.map(page => ({ ...page, text: "Remote text edit" })) };
  expect((await context.request.put(`/api/notebooks/${id}`, { headers: mutationHeaders, data: { id, document: cloud, revision: record.revision, mutationId: crypto.randomUUID() } })).status()).toBe(200);
  await page.unroute("**/api/v1/sync/commit");
  page.on("dialog", dialog => dialog.accept());
  await page.reload();
  await page.getByRole("button", { name: "Text", exact: true }).click();
  await expect(page.getByLabel("Page 1 text")).toHaveValue("Keep this local work.");
  await expect(page.getByRole("button", { name: "Save conflict copy" })).toBeVisible();
  await page.getByRole("button", { name: "Save conflict copy" }).click();
  await expect(page.getByLabel("Notebook title")).toHaveValue("Recovery notebook (conflict copy)");
  await expect(page.getByRole("status").filter({ hasText: "Saved to cloud" })).toBeVisible();
  const original = await (await context.request.get(`/api/notebooks/${id}`)).json();
  expect(original.document.title).toBe("Newer cloud version");
  expect(original.document.pages[0].text).toBe("Remote text edit");
  const copies = await (await context.request.get("/api/notebooks")).json();
  expect(copies).toHaveLength(2);
});

test("admin invitations send, resend, reject duplicates, and revoke existing sessions", async ({ page, request, context, browser }) => {
  await installSession(context, request);
  await page.goto("/admin");
  await page.getByRole("button", { name: "Invite someone", exact: true }).click();
  await page.getByLabel("Email address", { exact: true }).fill("friend@example.com");
  await page.getByRole("button", { name: "Send invitation", exact: true }).click();
  await expect(page.getByRole("status")).toContainText("Invitation sent");
  const row = page.getByRole("row").filter({ hasText: "friend@example.com" });
  await expect(row.getByRole("cell", { name: "Invited", exact: true })).toBeVisible();
  expect((await context.request.post("/api/admin/users", { headers: mutationHeaders, data: { email: "friend@example.com" } })).status()).toBe(409);
  await row.getByRole("button", { name: "Invite / resend" }).click();
  await expect.poll(async () => (await (await request.get(`${provider}/__test__/emails`)).json()).length).toBe(2);
  const emails = await (await request.get(`${provider}/__test__/emails`)).json();
  expect(emails.every((email: { type: string }) => email.type === "invite")).toBe(true);
  const member = await browser.newContext();
  try {
    const memberPage = await member.newPage();
    await memberPage.goto(emails[1].url);
    await expect(memberPage.getByRole("heading", { name: "Choose your password." })).toBeVisible();
    await memberPage.getByLabel("Password", { exact: true }).fill("member-password");
    await memberPage.getByLabel("Confirm password").fill("member-password");
    await memberPage.getByRole("button", { name: "Save password" }).click();
    await expect(memberPage.getByRole("heading", { name: "Your notebooks" })).toBeVisible();
    expect((await member.request.get("http://127.0.0.1:3101/api/admin/users")).status()).toBe(403);
    await row.getByRole("button", { name: "Revoke access" }).click();
    await page.getByRole("dialog").getByRole("button", { name: "Revoke access" }).click();
    await expect(row.getByRole("cell", { name: "Revoked", exact: true })).toBeVisible();
    expect((await member.request.get("http://127.0.0.1:3101/api/notebooks")).status()).toBe(403);
    await memberPage.goto("http://127.0.0.1:3101/notebooks");
    await expect(memberPage).toHaveURL(/\/login\?reason=forbidden$/);
  } finally { await member.close(); }
});

test.describe("mobile layout", () => {
  test.use({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true });
  test("private pages fit the viewport and workspace navigation is usable", async ({ page, request, context }, testInfo) => {
    await installSession(context, request);
    const id = crypto.randomUUID();
    await context.request.post("/api/notebooks", { headers: mutationHeaders, data: { id, document: newDocument("Mobile notebook"), mutationId: crypto.randomUUID() } });
    for (const path of ["/", "/notebooks", "/admin", `/notebooks/${id}`]) {
      await page.goto(path);
      if (path.includes(id)) await expect(page.getByRole("application", { name: "Drawing page 1" })).toBeVisible();
      expect(await page.evaluate(() => document.documentElement.scrollWidth), path).toBeLessThanOrEqual(390);
    }
    await page.screenshot({ path: testInfo.outputPath("mobile-canvas.png"), fullPage: true });
    await page.getByRole("button", { name: "Toggle workspace navigation" }).click();
    await expect(page.getByRole("navigation", { name: "Notebooks", exact: true }).getByRole("link", { name: /Mobile notebook/ })).toBeVisible();
    await page.getByLabel("Account menu", { exact: true }).click();
    await expect(page.getByRole("link", { name: "Account settings", exact: true })).toBeVisible();
    await page.screenshot({ path: testInfo.outputPath("mobile-account-menu.png"), fullPage: true });
    await page.keyboard.press("Escape");
    await expect(page.getByRole("link", { name: "Account settings", exact: true })).not.toBeVisible();
    await page.getByLabel("Account menu", { exact: true }).click();
    await page.getByRole("navigation", { name: "Workspace navigation" }).getByRole("link", { name: "Notebooks", exact: true }).click();
    await expect(page.getByRole("heading", { name: "Your notebooks" })).toBeVisible();
    await expect(page.getByRole("button", { name: "Toggle workspace navigation" })).toHaveAttribute("aria-expanded", "false");
  });
});
