import { test, expect } from "@playwright/test";

test("main routes render, navigation works, and unknown URLs have a recovery page", async ({ page, request }, testInfo) => {
  const health = await request.get("/api/v1/health");
  expect(health.status()).toBe(200);
  expect(health.headers()["cache-control"]).toBe("no-store");
  expect(await health.json()).toMatchObject({ status: "ok", service: "mynotes-api", apiVersion: "v1" });
  for (const path of ["/", "/login", "/invite", "/forgot-password", "/reset-password", "/notebooks", "/notebooks/everyday-ideas", "/admin", "/setup", "/auth/callback"]) {
    const response = await request.get(path);
    expect(response.status(), path).toBe(200);
  }
  await page.goto("/");
  await expect(page.getByRole("heading", { level: 1 })).toContainText("big ideas");
  await page.screenshot({ path: testInfo.outputPath("landing.png"), fullPage: true });
  await page.getByRole("link", { name: "Explore the workspace", exact: true }).click();
  await expect(page).toHaveURL(/\/notebooks$/);
  await expect(page.getByRole("heading", { name: "Your notebooks" })).toBeVisible();
  const missing = await page.goto("/missing-page");
  expect(missing?.status()).toBe(404);
  await page.getByRole("link", { name: "Back to notebook preview" }).click();
  await expect(page.getByRole("heading", { name: "Your notebooks" })).toBeVisible();
});

test("authentication previews validate forms without sending credentials or making external requests", async ({ page }, testInfo) => {
  const externalRequests: string[] = [];
  page.on("request", request => {
    if (!request.url().startsWith("http://127.0.0.1:3101/")) externalRequests.push(request.url());
  });
  await page.goto("/login");
  await page.getByLabel("Email address", { exact: true }).fill("reader@example.com");
  await page.getByLabel("Password", { exact: true }).fill("preview-password");
  await page.getByRole("button", { name: "Show password" }).click();
  await expect(page.getByLabel("Password", { exact: true })).toHaveAttribute("type", "text");
  await page.getByRole("button", { name: "Sign in", exact: true }).click();
  await expect(page.getByRole("status")).toContainText("not submitted or saved");
  await expect(page).toHaveURL(/\/login$/);
  await expect(page.getByLabel("Password", { exact: true })).toHaveValue("");
  await page.getByRole("button", { name: "Continue with Google" }).click();
  await expect(page.getByRole("status")).toContainText("No sign-in was attempted");
  await page.screenshot({ path: testInfo.outputPath("login.png"), fullPage: true });
  await page.getByRole("link", { name: "Forgot password?" }).click();
  await expect(page.getByRole("heading", { name: "Forgot your password?" })).toBeVisible();
  await page.getByLabel("Email address", { exact: true }).fill("reader@example.com");
  await page.getByRole("button", { name: "Send reset link" }).click();
  await expect(page.getByRole("status")).toContainText("no reset email was sent");
  expect(externalRequests).toEqual([]);
});

test("invitation and password-reset previews reject mismatched passwords", async ({ page }) => {
  for (const path of ["/invite", "/reset-password"]) {
    await page.goto(path);
    if (path === "/invite") await page.getByLabel("Invited email address").fill("invited@example.com");
    await page.getByLabel("Password", { exact: true }).fill("preview-password");
    await page.getByLabel("Confirm password").fill("different-password");
    await page.getByRole("button", { name: path === "/invite" ? "Set up my account" : "Update password" }).click();
    await expect(page.getByRole("form").getByRole("alert")).toContainText("don’t match");
    await page.getByLabel("Confirm password").fill("preview-password");
    await page.getByRole("button", { name: path === "/invite" ? "Set up my account" : "Update password" }).click();
    await expect(page.getByRole("status")).toContainText("Preview only");
  }
});

test("notebooks can be searched, created, and customized across workspace navigation", async ({ page }, testInfo) => {
  await page.goto("/notebooks");
  await page.getByRole("searchbox", { name: "Search notebooks" }).fill("missing idea");
  await expect(page.getByRole("heading", { name: "A thought waiting to be found." })).toBeVisible();
  await page.getByRole("button", { name: "Clear search" }).click();
  await page.getByRole("button", { name: "List view" }).click();
  await expect(page.getByRole("button", { name: "List view" })).toHaveAttribute("aria-pressed", "true");
  await page.getByRole("button", { name: "Grid view" }).click();
  await page.screenshot({ path: testInfo.outputPath("notebooks.png"), fullPage: true });
  await page.getByRole("button", { name: "New notebook" }).click();
  await expect(page.getByRole("dialog")).toBeVisible();
  await page.getByLabel("Notebook name").fill("Weekend sketches");
  await page.getByRole("button", { name: "Rose", exact: true }).click();
  await page.getByLabel("Paper template").selectOption("dots");
  await page.getByRole("button", { name: "Create preview notebook" }).click();
  await expect(page.getByLabel("Notebook title")).toHaveValue("Weekend sketches");
  await expect(page.getByLabel("Paper template")).toHaveValue("dots");
  await page.getByRole("button", { name: "Add page", exact: true }).first().click();
  await expect(page.getByRole("status").filter({ hasText: "Page 2 of 2" })).toBeVisible();
  await page.getByLabel("Paper template").selectOption("grid");
  await page.getByRole("button", { name: "Zoom in" }).click();
  await expect(page.getByLabel("Zoom level")).toHaveText("95%");
  await page.getByRole("link", { name: "Back to notebooks", exact: true }).click();
  await page.getByRole("searchbox", { name: "Search notebooks" }).fill("weekend");
  await expect(page.getByRole("status")).toHaveText("1 notebook found");
  await page.getByRole("link", { name: /Weekend sketches/ }).click();
  await expect(page.getByLabel("Paper template")).toHaveValue("grid");
  await expect(page.getByLabel("Current page").getByRole("option")).toHaveCount(2);
  await page.goto("/notebooks/everyday-ideas");
  await page.screenshot({ path: testInfo.outputPath("editor.png"), fullPage: true });
});

test("admin invitations update sample counts and reject duplicates without sending emails", async ({ page }, testInfo) => {
  await page.goto("/admin");
  const pending = page.locator("article").filter({ hasText: "Pending invitations" });
  await expect(pending.locator("strong")).toHaveText("1");
  await page.getByRole("button", { name: "Invite someone" }).click();
  await page.getByLabel("Email address", { exact: true }).fill("friend@example.com");
  await page.getByRole("button", { name: "Add preview invitation" }).click();
  await expect(page.getByRole("status")).toContainText("No email was sent");
  await expect(pending.locator("strong")).toHaveText("2");
  await page.getByRole("button", { name: "Invite someone" }).click();
  await page.getByLabel("Email address", { exact: true }).fill("friend@example.com");
  await page.getByRole("button", { name: "Add preview invitation" }).click();
  await expect(page.getByRole("dialog").getByRole("alert")).toContainText("already has");
  await page.keyboard.press("Escape");
  await expect(page.getByRole("dialog")).not.toBeVisible();
  await page.getByRole("button", { name: "Revoke preview invitation for friend@example.com" }).click();
  await expect(pending.locator("strong")).toHaveText("1");
  await page.getByRole("searchbox", { name: "Search people" }).fill("friend@example.com");
  await expect(page.getByRole("cell", { name: "Revoked", exact: true })).toBeVisible();
  await page.getByRole("searchbox", { name: "Search people" }).clear();
  await page.screenshot({ path: testInfo.outputPath("admin.png"), fullPage: true });
});

test.describe("mobile layout", () => {
  test.use({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true });

  test("pages fit the viewport and the collapsed workspace navigation is usable", async ({ page }, testInfo) => {
    for (const path of ["/", "/login", "/notebooks", "/admin", "/notebooks/everyday-ideas"]) {
      await page.goto(path);
      const documentWidth = await page.evaluate(() => document.documentElement.scrollWidth);
      expect(documentWidth, `${path} should not overflow the mobile viewport`).toBeLessThanOrEqual(390);
    }
    await page.getByRole("button", { name: "Toggle workspace navigation" }).click();
    await page.getByRole("navigation", { name: "Workspace navigation" }).getByRole("link", { name: "Administration" }).click();
    await expect(page.getByRole("heading", { name: "People & invitations" })).toBeVisible();
    await expect(page.getByRole("button", { name: "Toggle workspace navigation" })).toHaveAttribute("aria-expanded", "false");
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(390);
    await page.screenshot({ path: testInfo.outputPath("mobile-admin.png"), fullPage: true });
  });
});
