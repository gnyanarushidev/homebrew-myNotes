// Test-only HTTP fixture. Production authentication always talks to configured Supabase.
import { createServer } from "node:http";
import { createHash, randomUUID } from "node:crypto";
import { addCloudUser, cloudRequest, resetCloud } from "./cloud-fixture.mjs";

const appOrigin = "http://127.0.0.1:3101";
const initialUsers = {
  admin: { id: "11111111-1111-4111-8111-111111111111", email: "admin@example.com", email_confirmed_at: "2026-01-01T00:00:00Z", aud: "authenticated", role: "authenticated", app_metadata: { provider: "email" }, user_metadata: { name: "Admin", profile: "x".repeat(2600) } },
  member: { id: "22222222-2222-4222-8222-222222222222", email: "member@example.com", email_confirmed_at: "2026-01-01T00:00:00Z", aud: "authenticated", role: "authenticated", app_metadata: { role: "admin" }, user_metadata: { role: "admin", mynotes_access: "active" } },
  unverified: { id: "33333333-3333-4333-8333-333333333333", email: "admin@example.com", aud: "authenticated", role: "authenticated", app_metadata: {}, user_metadata: {} },
  invited: { id: "44444444-4444-4444-8444-444444444444", email: "invited@example.com", email_confirmed_at: "2026-01-01T00:00:00Z", aud: "authenticated", role: "authenticated", app_metadata: { mynotes_access: "active" }, user_metadata: {} },
};
let users = structuredClone(initialUsers);
const notebooks = new Map();
let password = "initial-password";
let oauthUser = "admin";
const sessions = new Map();
const refreshTokens = new Map();
const rotatedTokens = new Map();
const codes = new Map();
const emails = [];

function session(user, expired = false) {
  const exp = Math.floor(Date.now() / 1000) + (expired ? -60 : 3600);
  const encode = value => Buffer.from(JSON.stringify(value)).toString("base64url");
  const access_token = `${encode({ alg: "HS256", typ: "JWT" })}.${encode({ sub: user.id, exp, aud: "authenticated", iat: Math.floor(Date.now() / 1000), session_id: randomUUID() })}.test-signature`;
  const refresh_token = randomUUID();
  const value = { access_token, refresh_token, expires_in: 3600, expires_at: exp, token_type: "bearer", user };
  sessions.set(access_token, value);
  refreshTokens.set(refresh_token, user);
  return value;
}

function emailLink(type, redirect = `${appOrigin}/auth/callback?next=%2Freset-password`, user = users.admin) {
  const code = randomUUID();
  codes.set(code, { user });
  const url = new URL(redirect);
  url.searchParams.set("token_hash", code);
  url.searchParams.set("type", type);
  return url.toString();
}

const server = createServer(async (request, response) => {
  const url = new URL(request.url, "http://127.0.0.1:54329");
  const send = (status, body) => { response.writeHead(status, { "Content-Type": "application/json" }); response.end(JSON.stringify(body)); };
  const chunks = [];
  for await (const chunk of request) chunks.push(chunk);
  const buffer = Buffer.concat(chunks);
  if (await cloudRequest(request, response, url, buffer)) return;
  const raw = buffer.toString("utf8");
  let body = {};
  try { if (raw) body = JSON.parse(raw); } catch { return send(400, { message: "Invalid JSON" }); }

  if (url.pathname === "/__test__/reset") {
    password = "initial-password";
    oauthUser = "admin";
    users = structuredClone(initialUsers); notebooks.clear();
    await resetCloud(Object.values(users).map(user => user.id));
    sessions.clear(); refreshTokens.clear(); rotatedTokens.clear(); codes.clear(); emails.length = 0;
    return send(200, { ok: true });
  }
  if (url.pathname === "/__test__/session") return send(200, session(users[url.searchParams.get("user") ?? "admin"], url.searchParams.has("expired")));
  if (url.pathname === "/__test__/invite") return send(200, { url: emailLink("invite") });
  if (url.pathname === "/__test__/emails") return send(200, emails);
  if (url.pathname === "/__test__/oauth") { oauthUser = body.user; return send(200, { ok: true }); }
  if (url.pathname === "/auth/v1/settings") return send(200, { external: { email: true, google: true }, disable_signup: true });
  if (url.pathname === "/auth/v1/authorize") {
    const code = randomUUID();
    codes.set(code, { challenge: url.searchParams.get("code_challenge"), user: users[oauthUser] });
    const redirect = new URL(url.searchParams.get("redirect_to"));
    redirect.searchParams.set("code", code);
    response.writeHead(302, { Location: redirect.toString() }); response.end(); return;
  }
  if (url.pathname === "/auth/v1/token") {
    const grant = url.searchParams.get("grant_type");
    if (grant === "password" && body.email === users.admin.email && body.password === password) return send(200, session(users.admin));
    const member = Object.values(users).find(user => user.email === body.email && user.email !== users.admin.email);
    if (grant === "password" && member && body.password === "member-password") return send(200, session(member));
    if (grant === "refresh_token" && refreshTokens.has(body.refresh_token)) {
      // Supabase permits brief token reuse for concurrent SSR/prefetch requests.
      const rotated = rotatedTokens.get(body.refresh_token);
      if (rotated && Date.now() - rotated.at < 10_000) return send(200, rotated.session);
      const user = refreshTokens.get(body.refresh_token);
      const next = session(user);
      rotatedTokens.set(body.refresh_token, { session: next, at: Date.now() });
      return send(200, next);
    }
    if (grant === "pkce" && codes.has(body.auth_code)) {
      const challenge = createHash("sha256").update(body.code_verifier ?? "").digest("base64url");
      const value = codes.get(body.auth_code);
      if (value.challenge === challenge) { codes.delete(body.auth_code); return send(200, session(value.user)); }
    }
    return send(400, { code: "invalid_credentials", msg: "Invalid credentials" });
  }
  if (url.pathname === "/auth/v1/recover") {
    const user = Object.values(users).find(user => user.email === body.email);
    if (user) emails.push({ type: "recovery", email: body.email, url: emailLink("recovery", url.searchParams.get("redirect_to") ?? undefined, user) });
    return send(200, {});
  }
  if (url.pathname === "/auth/v1/verify") {
    if (body.token_hash === "valid-invite" && body.type === "invite") return send(200, session(users.admin));
    const value = codes.get(body.token_hash);
    if (value?.user && !value.challenge) {
      codes.delete(body.token_hash);
      value.user.email_confirmed_at = new Date().toISOString();
      return send(200, session(value.user));
    }
    return send(403, { code: "otp_expired", msg: "Link expired" });
  }
  if (url.pathname === "/auth/v1/admin/users") {
    if (request.headers.apikey !== "sb_secret_test") return send(403, { msg: "Forbidden" });
    return send(200, { users: Object.values(users).filter(user => user !== users.unverified), aud: "authenticated" });
  }
  if (url.pathname.startsWith("/auth/v1/admin/users/") && request.method === "PUT") {
    if (request.headers.apikey !== "sb_secret_test") return send(403, { msg: "Forbidden" });
    const user = Object.values(users).find(user => user.id === url.pathname.split("/").pop());
    if (!user) return send(404, { msg: "User not found" });
    user.app_metadata = { ...user.app_metadata, ...body.app_metadata };
    return send(200, user);
  }
  if (url.pathname === "/auth/v1/invite") {
    if (request.headers.apikey !== "sb_secret_test") return send(403, { msg: "Forbidden" });
    let user = Object.values(users).find(user => user.email === body.email);
    user ??= users[body.email] = { id: randomUUID(), email: body.email, aud: "authenticated", role: "authenticated", app_metadata: {}, user_metadata: {}, created_at: new Date().toISOString() };
    user.invited_at = new Date().toISOString();
    await addCloudUser(user.id);
    emails.push({ type: "invite", email: body.email, url: emailLink("invite", url.searchParams.get("redirect_to") ?? undefined, user) });
    return send(200, user);
  }
  // A PostgREST-shaped fixture for HTTP integration tests, not a substitute for SQL/RLS checks.
  if (url.pathname === "/rest/v1/mynotes_notebooks") {
    if (request.headers.apikey !== "sb_secret_test") return send(403, { message: "Permission denied" });
    const matches = row => ["id", "owner_id", "revision"].every(key => !url.searchParams.has(key) || String(row[key]) === url.searchParams.get(key).slice(3));
    const present = row => ({ ...row, title: row.document.title, template: row.document.template, color: row.document.color, page_count: row.document.pages.length });
    let rows = [...notebooks.values()].filter(matches);
    if (request.method === "POST") {
      if (notebooks.has(body.id)) return send(409, { code: "23505" });
      const row = { ...body, revision: 1, created_at: new Date().toISOString(), updated_at: new Date().toISOString() };
      notebooks.set(row.id, row); rows = [row];
    } else if (request.method === "PATCH") {
      rows.forEach(row => Object.assign(row, body));
    } else if (request.method === "DELETE") {
      rows.forEach(row => notebooks.delete(row.id));
    } else {
      const search = url.searchParams.get("search_text")?.slice(7, -1).replace(/\\([\\%_])/g, "$1").toLowerCase();
      if (search) rows = rows.filter(row => `${row.document.title} ${row.document.pages.map(page => page.text).join(" ")}`.toLowerCase().includes(search));
      rows.sort((a, b) => b.updated_at.localeCompare(a.updated_at) || a.id.localeCompare(b.id));
      const offset = Number(url.searchParams.get("offset") ?? 0);
      rows = rows.slice(offset, offset + Number(url.searchParams.get("limit") ?? 1000));
    }
    if (request.headers.accept?.includes("application/vnd.pgrst.object+json")) {
      if (rows.length !== 1) return send(406, { code: "PGRST116", details: `The result contains ${rows.length} rows` });
      return send(200, present(rows[0]));
    }
    return send(200, rows.map(present));
  }
  const token = request.headers.authorization?.replace(/^Bearer /, "");
  const active = sessions.get(token);
  if (!active || active.expires_at <= Date.now() / 1000) return send(401, { code: "bad_jwt", msg: "Invalid session" });
  if (url.pathname === "/auth/v1/user" && request.method === "GET") return send(200, active.user);
  if (url.pathname === "/auth/v1/user" && request.method === "PUT") {
    if (active.user.id === users.admin.id && typeof body.password === "string") password = body.password;
    return send(200, active.user);
  }
  if (url.pathname === "/auth/v1/logout") {
    sessions.delete(token); refreshTokens.delete(active.refresh_token);
    return send(200, {});
  }
  send(404, { message: "Unknown test endpoint" });
});

server.listen(54329, "127.0.0.1", () => console.log("Test authentication provider ready."));
