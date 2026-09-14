// Test-only HTTP fixture. Production authentication always talks to configured Supabase.
import { createServer } from "node:http";
import { createHash, randomUUID } from "node:crypto";

const appOrigin = "http://127.0.0.1:3101";
const users = {
  admin: { id: "11111111-1111-4111-8111-111111111111", email: "admin@example.com", email_confirmed_at: "2026-01-01T00:00:00Z", aud: "authenticated", role: "authenticated", app_metadata: { provider: "email" }, user_metadata: { name: "Admin", profile: "x".repeat(2600) } },
  member: { id: "22222222-2222-4222-8222-222222222222", email: "member@example.com", email_confirmed_at: "2026-01-01T00:00:00Z", aud: "authenticated", role: "authenticated", app_metadata: { role: "admin" }, user_metadata: { role: "admin" } },
  unverified: { id: "33333333-3333-4333-8333-333333333333", email: "admin@example.com", aud: "authenticated", role: "authenticated", app_metadata: {}, user_metadata: {} },
};
let password = "initial-password";
const sessions = new Map();
const refreshTokens = new Map();
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

function emailLink(type, redirect = `${appOrigin}/auth/callback?next=%2Freset-password`) {
  const value = session(users.admin);
  const url = new URL(redirect);
  url.hash = new URLSearchParams({ access_token: value.access_token, refresh_token: value.refresh_token, token_type: "bearer", expires_in: "3600", type }).toString();
  return url.toString();
}

const server = createServer(async (request, response) => {
  const url = new URL(request.url, "http://127.0.0.1:54329");
  const send = (status, body) => { response.writeHead(status, { "Content-Type": "application/json" }); response.end(JSON.stringify(body)); };
  let raw = "";
  for await (const chunk of request) raw += chunk;
  let body = {};
  try { if (raw) body = JSON.parse(raw); } catch { return send(400, { message: "Invalid JSON" }); }

  if (url.pathname === "/__test__/reset") {
    password = "initial-password";
    sessions.clear(); refreshTokens.clear(); codes.clear(); emails.length = 0;
    return send(200, { ok: true });
  }
  if (url.pathname === "/__test__/session") return send(200, session(users[url.searchParams.get("user") ?? "admin"], url.searchParams.has("expired")));
  if (url.pathname === "/__test__/invite") return send(200, { url: emailLink("invite") });
  if (url.pathname === "/__test__/emails") return send(200, emails);
  if (url.pathname === "/auth/v1/settings") return send(200, { external: { email: true, google: true }, disable_signup: true });
  if (url.pathname === "/auth/v1/authorize") {
    const code = randomUUID();
    codes.set(code, url.searchParams.get("code_challenge"));
    const redirect = new URL(url.searchParams.get("redirect_to"));
    redirect.searchParams.set("code", code);
    response.writeHead(302, { Location: redirect.toString() }); response.end(); return;
  }
  if (url.pathname === "/auth/v1/token") {
    const grant = url.searchParams.get("grant_type");
    if (grant === "password" && body.email === users.admin.email && body.password === password) return send(200, session(users.admin));
    if (grant === "refresh_token" && refreshTokens.has(body.refresh_token)) {
      const user = refreshTokens.get(body.refresh_token);
      refreshTokens.delete(body.refresh_token);
      return send(200, session(user));
    }
    if (grant === "pkce" && codes.has(body.auth_code)) {
      const challenge = createHash("sha256").update(body.code_verifier ?? "").digest("base64url");
      if (codes.get(body.auth_code) === challenge) { codes.delete(body.auth_code); return send(200, session(users.admin)); }
    }
    return send(400, { code: "invalid_credentials", msg: "Invalid credentials" });
  }
  if (url.pathname === "/auth/v1/recover") {
    emails.push({ type: "recovery", url: emailLink("recovery", url.searchParams.get("redirect_to") ?? undefined) });
    return send(200, {});
  }
  if (url.pathname === "/auth/v1/verify") {
    if (body.token_hash === "valid-invite" && body.type === "invite") return send(200, session(users.admin));
    return send(403, { code: "otp_expired", msg: "Link expired" });
  }
  if (url.pathname === "/auth/v1/admin/users") {
    if (request.headers.apikey !== "sb_secret_test") return send(403, { msg: "Forbidden" });
    return send(200, { users: [users.admin], aud: "authenticated" });
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
