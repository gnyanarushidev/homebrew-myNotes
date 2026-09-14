import "server-only";

import { createServerClient, type CookieOptions } from "@supabase/ssr";
import { createClient, type User } from "@supabase/supabase-js";
import { NextRequest, NextResponse } from "next/server";
import { AUTH_COOKIE, type AuthSettings } from "./settings";

export const PRIVATE_HEADERS = {
  "Cache-Control": "private, no-store, max-age=0",
  "Referrer-Policy": "no-referrer",
  Vary: "Cookie",
};

export function isVerifiedAdmin(user: User | null, settings: AuthSettings): user is User & { email: string } {
  return Boolean(user?.id && user.email_confirmed_at && !user.is_anonymous && user.email?.toLowerCase() === settings.adminEmail);
}

export function authCookieOptions(settings: AuthSettings) {
  return { name: AUTH_COOKIE, httpOnly: true, secure: settings.appOrigin.startsWith("https:"), sameSite: "lax" as const, path: "/" };
}

export const authFetch: typeof fetch = (input, init) => fetch(input, {
  ...init,
  cache: "no-store",
  signal: init?.signal ?? AbortSignal.timeout(15_000),
});

export function createRequestAuth(request: NextRequest, settings: AuthSettings) {
  const changes = new Map<string, { name: string; value: string; options: CookieOptions }>();
  const cacheHeaders = new Headers(PRIVATE_HEADERS);
  const client = createServerClient(settings.supabaseUrl, settings.publishableKey, {
    cookieOptions: authCookieOptions(settings),
    global: { fetch: authFetch },
    cookies: {
      getAll: () => request.cookies.getAll(),
      setAll(values, headers) {
        for (const cookie of values) {
          request.cookies.set(cookie.name, cookie.value);
          changes.set(cookie.name, cookie);
        }
        for (const [name, value] of Object.entries(headers ?? {})) cacheHeaders.set(name, value);
      },
    },
  });

  function finish(response: NextResponse) {
    cacheHeaders.forEach((value, name) => response.headers.set(name, value));
    for (const cookie of changes.values()) response.cookies.set(cookie.name, cookie.value, cookie.options);
    return response;
  }

  function clearSession() {
    // Clear every chunk, even if token revocation fails during a network outage.
    for (const cookie of request.cookies.getAll()) {
      if (cookie.name === AUTH_COOKIE || cookie.name.startsWith(`${AUTH_COOKIE}.`) || cookie.name.startsWith(`${AUTH_COOKIE}-`)) {
        changes.set(cookie.name, {
          name: cookie.name,
          value: "",
          options: { httpOnly: true, secure: settings.appOrigin.startsWith("https:"), sameSite: "lax", path: "/", maxAge: 0 },
        });
      }
    }
  }

  return { client, finish, clearSession };
}

export function createEmailAuth(settings: AuthSettings) {
  // Email links must also work in a different browser/device from the request.
  return createClient(settings.supabaseUrl, settings.publishableKey, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false, flowType: "implicit" },
    global: { fetch: authFetch },
  });
}
