import "server-only";

import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { cache } from "react";
import { authCookieOptions, authFetch, isVerifiedAdmin } from "./client";
import { getAuthSettings, AuthConfigurationError } from "./settings";

export const getAdminAccess = cache(async () => {
  try {
    const settings = getAuthSettings();
    const store = await cookies();
    const client = createServerClient(settings.supabaseUrl, settings.publishableKey, {
      cookieOptions: authCookieOptions(settings),
      global: { fetch: authFetch },
      cookies: {
        getAll: () => store.getAll(),
        // The proxy writes refreshed cookies before server components render.
        setAll() {},
      },
    });
    const { data, error } = await client.auth.getUser();
    if (error || !data.user) return { status: "anonymous" as const };
    if (!isVerifiedAdmin(data.user, settings)) return { status: "forbidden" as const };
    return { status: "admin" as const, user: { id: data.user.id, email: data.user.email } };
  } catch (error) {
    return { status: error instanceof AuthConfigurationError ? "unconfigured" as const : "unavailable" as const };
  }
});

export async function requireAdmin() {
  const access = await getAdminAccess();
  if (access.status !== "admin") redirect(`/login?reason=${access.status}`);
  return access.user;
}
