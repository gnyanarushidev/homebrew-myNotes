import { NextRequest, NextResponse } from "next/server";
import { authFetch, accountHome, createEmailAuth, createRequestAuth, isAllowedAccount, isVerifiedAdmin, PRIVATE_HEADERS } from "@/server/auth/client";
import { canRecover } from "@/server/service";
import { AuthConfigurationError, authDestination, callbackUrl, getAuthSettings } from "@/server/auth/settings";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

type Context = { params: Promise<{ action: string }> };
const json = (body: object, status = 200) => NextResponse.json(body, { status, headers: PRIVATE_HEADERS });
const emailValue = (value: unknown) => typeof value === "string" && value.length <= 254 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value.trim()) ? value.trim().toLowerCase() : null;

export async function GET(request: NextRequest, context: Context) {
  try {
    const { action } = await context.params;
    const settings = getAuthSettings();
    const auth = createRequestAuth(request, settings);
    if (action === "google") {
      const providers = await authFetch(`${settings.supabaseUrl}/auth/v1/settings`, { headers: { apikey: settings.publishableKey } });
      if (!providers.ok || !(await providers.json()).external?.google) {
        return auth.finish(NextResponse.redirect(new URL("/login?reason=google-unavailable", settings.appOrigin)));
      }
      const { data, error } = await auth.client.auth.signInWithOAuth({ provider: "google", options: { redirectTo: callbackUrl(settings) } });
      if (error || !data.url) return auth.finish(NextResponse.redirect(new URL("/login?reason=oauth-failed", settings.appOrigin)));
      return auth.finish(NextResponse.redirect(data.url));
    }
    if (action === "session") {
      const { data, error } = await auth.client.auth.getUser();
      if (error || !data.user) return auth.finish(json({ error: "Sign in to continue." }, 401));
      if (!isAllowedAccount(data.user, settings)) return auth.finish(json({ error: "This account has not been invited or its access was revoked." }, 403));
      return auth.finish(json({ user: { id: data.user.id, email: data.user.email }, role: isVerifiedAdmin(data.user, settings) ? "admin" : "member" }));
    }
    return json({ error: "Not found." }, 404);
  } catch (error) {
    return json({ error: error instanceof AuthConfigurationError ? error.message : "Authentication is temporarily unavailable." }, 503);
  }
}

export async function POST(request: NextRequest, context: Context) {
  let auth: ReturnType<typeof createRequestAuth> | undefined;
  try {
    const { action } = await context.params;
    const settings = getAuthSettings();
    if (request.headers.get("origin") !== settings.appOrigin) return json({ error: "Request origin is not allowed." }, 403);
    if (!request.headers.get("content-type")?.startsWith("application/json")) return json({ error: "Expected JSON." }, 415);
    if (Number(request.headers.get("content-length") ?? 0) > 16_384) return json({ error: "Request is too large." }, 413);
    let body: Record<string, unknown>;
    try {
      body = await request.json();
      if (!body || typeof body !== "object" || Array.isArray(body)) return json({ error: "Invalid request." }, 400);
    } catch { return json({ error: "Invalid JSON." }, 400); }
    auth = createRequestAuth(request, settings);

    if (action === "login") {
      const email = emailValue(body.email);
      if (!email || typeof body.password !== "string" || !body.password || body.password.length > 1024) {
        return json({ error: "Unable to sign in. Check your email and password." }, 401);
      }
      const { data, error } = await auth.client.auth.signInWithPassword({ email, password: body.password });
      if (error || !isAllowedAccount(data.user, settings)) {
        auth.clearSession();
        return auth.finish(json({ error: "Unable to sign in. Check your credentials and invitation status." }, 401));
      }
      return auth.finish(json({ next: accountHome(data.user, settings) }));
    }

    if (action === "recovery") {
      const email = emailValue(body.email);
      if (!email) return json({ error: "Enter a valid email address." }, 400);
      if (await canRecover(email)) {
        const { error } = await createEmailAuth(settings).auth.resetPasswordForEmail(email, { redirectTo: callbackUrl(settings, true) });
        if (error) return json({ error: "The reset email could not be sent. Please wait and try again." }, 503);
      }
      return json({ message: "If this email has application access, a password-reset link will arrive shortly." });
    }

    if (action === "complete") {
      if (typeof body.access_token !== "string" || typeof body.refresh_token !== "string" || body.access_token.length > 8192 || body.refresh_token.length > 4096) {
        return json({ error: "This sign-in link is invalid or expired." }, 400);
      }
      const { error } = await auth.client.auth.setSession({ access_token: body.access_token, refresh_token: body.refresh_token });
      const { data } = error ? { data: { user: null } } : await auth.client.auth.getUser();
      if (error || !isAllowedAccount(data.user, settings)) {
        auth.clearSession();
        return auth.finish(json({ error: "This link is invalid, expired, or belongs to a different account." }, 403));
      }
      return auth.finish(json({ next: body.type === "invite" || body.type === "recovery" || authDestination(typeof body.next === "string" ? body.next : null) === "/reset-password" ? "/reset-password" : accountHome(data.user, settings) }));
    }

    if (action === "logout") {
      try { await auth.client.auth.signOut({ scope: "local" }); } catch { /* Local sign-out still completes when Supabase is unavailable. */ }
      auth.clearSession();
      return auth.finish(json({ next: "/login" }));
    }

    if (action === "password") {
      const { data, error } = await auth.client.auth.getUser();
      if (error || !data.user) return auth.finish(json({ error: "Open a fresh password-setup link or sign in again." }, 401));
      if (!isAllowedAccount(data.user, settings)) return auth.finish(json({ error: "Application access is required." }, 403));
      if (typeof body.password !== "string" || body.password.length < 8 || body.password.length > 128) {
        return auth.finish(json({ error: "Use a password between 8 and 128 characters." }, 400));
      }
      const { error: updateError } = await auth.client.auth.updateUser({ password: body.password });
      if (updateError) return auth.finish(json({ error: "The password could not be updated. Check the password requirements or request a fresh link." }, 400));
      return auth.finish(json({ next: accountHome(data.user, settings) }));
    }
    return json({ error: "Not found." }, 404);
  } catch (error) {
    const response = json({ error: error instanceof AuthConfigurationError ? error.message : "Authentication is temporarily unavailable. Please try again." }, 503);
    return auth ? auth.finish(response) : response;
  }
}
