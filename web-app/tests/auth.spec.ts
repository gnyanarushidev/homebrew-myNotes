import { test, expect } from "@playwright/test";
import { origin, provider, installSession } from "./support/session";

test.describe.configure({ mode: "default" });
test.beforeEach(async ({ request }) => { await request.post(`${provider}/__test__/reset`); });

test("admin invitation verifies the email, sets a password, and supports real sign-in/logout", async ({ page, request, context }) => {
  const invitation = await (await request.get(`${provider}/__test__/invite`)).json();
  await page.goto(invitation.url);
  await expect(page.getByRole("heading", { name: "Choose your password." })).toBeVisible();
  expect(page.url()).not.toContain("access_token");
  await page.getByLabel("Password", { exact: true }).fill("new-admin-password");
  await page.getByLabel("Confirm password").fill("different-password");
  await page.getByRole("button", { name: "Save password" }).click();
  await expect(page.getByRole("form").getByRole("alert")).toContainText("don’t match");
  await page.getByLabel("Confirm password").fill("new-admin-password");
  await page.getByRole("button", { name: "Save password" }).click();
  await expect(page.getByRole("heading", { name: "Welcome, administrator." })).toBeVisible();
  await expect(page.getByText("admin@example.com", { exact: true })).toBeVisible();
  const cookies = (await context.cookies()).filter(cookie => cookie.name.startsWith("mynotes-auth"));
  expect(cookies.length).toBeGreaterThan(0);
  expect(cookies.every(cookie => cookie.httpOnly && cookie.sameSite === "Lax")).toBe(true);
  expect(await page.evaluate(() => document.cookie)).not.toContain("mynotes-auth");
  await page.getByRole("button", { name: "Sign out" }).click();
  await expect(page.getByRole("heading", { name: "Welcome back." })).toBeVisible();
  expect((await context.cookies()).filter(cookie => cookie.name.startsWith("mynotes-auth"))).toHaveLength(0);
  await page.getByLabel("Email address").fill("admin@example.com");
  await page.getByLabel("Password", { exact: true }).fill("new-admin-password");
  await page.getByRole("button", { name: "Sign in", exact: true }).click();
  await expect(page.getByRole("heading", { name: "Welcome, administrator." })).toBeVisible();
});

test("anonymous access, bad passwords, and cross-origin mutations are rejected", async ({ page, request }) => {
  await page.goto("/admin");
  await expect(page).toHaveURL(/\/login\?reason=anonymous$/);
  const session = await request.get("/api/auth/session");
  expect(session.status()).toBe(401);
  expect(session.headers()["cache-control"]).toContain("no-store");
  const csrf = await request.post("/api/auth/login", { headers: { Origin: "https://untrusted.example" }, data: { email: "admin@example.com", password: "initial-password" } });
  expect(csrf.status()).toBe(403);
  await page.getByLabel("Email address").fill("admin@example.com");
  await page.getByLabel("Password", { exact: true }).fill("wrong-password");
  await page.getByRole("button", { name: "Sign in", exact: true }).click();
  await expect(page.getByRole("form").getByRole("alert")).toContainText("Unable to sign in");
});

test("verified non-admin and unverified admin emails cannot open privileged pages or APIs", async ({ page, request, context }) => {
  for (const user of ["member", "unverified"]) {
    await context.clearCookies();
    await installSession(context, request, `?user=${user}`);
    await page.goto("/admin");
    await expect(page).toHaveURL(/\/login\?reason=forbidden$/);
    expect((await context.request.get("/api/auth/session")).status()).toBe(403);
    expect((await context.request.post("/api/auth/password", { headers: { Origin: origin }, data: { password: "forbidden-password" } })).status()).toBe(403);
  }
});

test("forged cookie user data is rejected and expired valid sessions refresh", async ({ page, context, request }) => {
  const session = await (await request.get(`${provider}/__test__/session?user=member`)).json();
  session.access_token = session.access_token.replace("test-signature", "forged-signature");
  session.user.email = "admin@example.com";
  session.user.app_metadata.role = "admin";
  await context.addCookies([{ name: "mynotes-auth", value: `base64-${Buffer.from(JSON.stringify(session)).toString("base64url")}`, url: origin }]);
  await page.goto("/admin");
  await expect(page).toHaveURL(/\/login\?reason=anonymous$/);
  await context.clearCookies();
  await installSession(context, request, "?expired=1");
  await page.goto("/admin");
  await expect(page.getByRole("heading", { name: "Welcome, administrator." })).toBeVisible();
  expect((await context.request.get("/api/auth/session")).status()).toBe(200);
});

test("Google OAuth uses a PKCE callback and produces an authorized admin session", async ({ page, context }) => {
  await page.goto("/login");
  await page.getByRole("button", { name: "Continue with Google" }).click();
  await expect(page.getByRole("heading", { name: "Welcome, administrator." })).toBeVisible();
  const response = await context.request.get("/api/auth/session");
  expect(await response.json()).toMatchObject({ role: "admin", user: { email: "admin@example.com" } });
});

test("password recovery and token-hash invitations work; expired links fail safely", async ({ page, request }) => {
  await page.goto("/forgot-password");
  await page.getByLabel("Email address").fill("admin@example.com");
  await page.getByRole("button", { name: "Send reset link" }).click();
  await expect(page.getByRole("status")).toContainText("password-reset link");
  const emails = await (await request.get(`${provider}/__test__/emails`)).json();
  expect(emails).toHaveLength(1);
  await page.goto(emails[0].url);
  await expect(page.getByRole("heading", { name: "Choose your password." })).toBeVisible();
  await page.context().clearCookies();
  await page.goto("/auth/callback?token_hash=expired&type=invite&next=https://untrusted.example");
  await expect(page).toHaveURL(/\/login\?reason=link-invalid$/);
  await page.goto("/auth/callback?token_hash=valid-invite&type=invite");
  await expect(page.getByRole("heading", { name: "Choose your password." })).toBeVisible();
});

test("password and Google sign-in admit invited identities and reject uninvited identities", async ({ page, request, context }) => {
  for (const user of ["invited", "member"]) {
    await context.clearCookies();
    const login = await context.request.post("/api/auth/login", { headers: { Origin: origin }, data: { email: `${user}@example.com`, password: "member-password" } });
    expect(login.status()).toBe(user === "invited" ? 200 : 401);
    if (user === "invited") expect(await login.json()).toMatchObject({ next: "/notebooks" });
    await context.clearCookies();
    await request.post(`${provider}/__test__/oauth`, { data: { user } });
    await page.goto("/login");
    await page.getByRole("button", { name: "Continue with Google" }).click();
    if (user === "invited") {
      await expect(page.getByRole("heading", { name: "Your notebooks" })).toBeVisible();
      const session = await (await context.request.get("/api/auth/session")).json();
      expect(session).toMatchObject({ role: "member", user: { email: "invited@example.com" } });
    } else {
      await expect(page).toHaveURL(/\/login\?reason=link-invalid$/);
      expect((await context.request.get("/api/notebooks")).status()).toBe(401);
    }
  }
});

test("default email-link fragments become private cookies and are removed from the URL", async ({ page, request, context }) => {
  const session = await (await request.get(`${provider}/__test__/session?user=invited`)).json();
  const fragment = new URLSearchParams({ access_token: session.access_token, refresh_token: session.refresh_token, type: "invite", token_type: "bearer", expires_in: "3600" });
  await page.goto(`/auth/callback#${fragment}`);
  await expect(page.getByRole("heading", { name: "Choose your password." })).toBeVisible();
  expect(page.url()).not.toContain("access_token");
  expect((await context.request.get("/api/auth/session")).status()).toBe(200);
  expect(await page.evaluate(() => document.cookie)).not.toContain("mynotes-auth");
});
