import "server-only";

export const AUTH_COOKIE = "mynotes-auth";

export class AuthConfigurationError extends Error {
  constructor() {
    super("Authentication is not configured for this deployment.");
  }
}

function origin(value: string | undefined) {
  try {
    const url = new URL(value ?? "");
    const local = ["localhost", "127.0.0.1", "[::1]"].includes(url.hostname);
    if (url.username || url.password || url.search || url.hash || url.pathname !== "/") throw new Error();
    if (url.protocol !== "https:" && !(url.protocol === "http:" && local)) throw new Error();
    return url.origin;
  } catch {
    throw new AuthConfigurationError();
  }
}

// Read at request time. No configuration or credentials are passed to client components.
export function getAuthSettings(env: NodeJS.ProcessEnv = process.env) {
  const publishableKey = env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY?.trim();
  const adminEmail = env.ADMIN_EMAIL?.trim().toLowerCase();
  if (!publishableKey || !adminEmail || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(adminEmail)) {
    throw new AuthConfigurationError();
  }
  return {
    supabaseUrl: origin(env.NEXT_PUBLIC_SUPABASE_URL),
    appOrigin: origin(env.APP_URL),
    publishableKey,
    adminEmail,
  };
}

export type AuthSettings = ReturnType<typeof getAuthSettings>;

export function callbackUrl(settings: AuthSettings, passwordSetup = false) {
  const url = new URL("/auth/callback", settings.appOrigin);
  if (passwordSetup) url.searchParams.set("next", "/reset-password");
  return url.toString();
}

export function authDestination(value: string | null) {
  return value === "/reset-password" ? "/reset-password" : "/admin";
}
