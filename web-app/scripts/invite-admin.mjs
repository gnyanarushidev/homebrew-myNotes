import nextEnv from "@next/env";
import { createClient } from "@supabase/supabase-js";
import { fileURLToPath } from "node:url";

nextEnv.loadEnvConfig(fileURLToPath(new URL("../", import.meta.url)), false);

const checkOnly = process.argv.includes("--check");
const env = process.env;
const email = env.ADMIN_EMAIL?.trim().toLowerCase();

function configuredOrigin(value) {
  const url = new URL(value ?? "");
  const local = ["localhost", "127.0.0.1", "[::1]"].includes(url.hostname);
  if (url.username || url.password || url.search || url.hash || url.pathname !== "/" || (url.protocol !== "https:" && !(url.protocol === "http:" && local))) {
    throw new Error("Invalid origin");
  }
  return url.origin;
}

async function main() {
  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || !env.SUPABASE_SECRET_KEY || !env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY) {
    console.error("Set ADMIN_EMAIL, SUPABASE_SECRET_KEY, and NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY in .env.local.");
    process.exitCode = 1;
    return;
  }
  const supabaseUrl = configuredOrigin(env.NEXT_PUBLIC_SUPABASE_URL);
  const appOrigin = configuredOrigin(env.APP_URL);
  const redirectTo = `${appOrigin}/auth/callback?next=%2Freset-password`;
  const options = {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false, flowType: "implicit" },
    global: { fetch: (input, init) => fetch(input, { ...init, signal: init?.signal ?? AbortSignal.timeout(15_000) }) },
  };
  const admin = createClient(supabaseUrl, env.SUPABASE_SECRET_KEY, options);
  let existing;
  for (let page = 1; ; page++) {
    const { data, error } = await admin.auth.admin.listUsers({ page, perPage: 100 });
    if (error) {
      console.error(`Unable to check the admin account (HTTP ${error.status ?? "unknown"}). Verify the Supabase project and secret key.`);
      process.exitCode = 1;
      return;
    }
    existing = data.users.find(user => user.email?.toLowerCase() === email);
    if (existing || data.users.length < 100) break;
  }

  console.log(`Application URL: ${appOrigin}`);
  console.log(existing ? "The configured admin account already exists." : "The configured admin account has not been created yet.");
  if (checkOnly) {
    console.log("Configuration check complete. No invitation or recovery email was sent.");
    return;
  }

  const confirmed = Boolean(existing?.email_confirmed_at);
  const result = confirmed
    ? await createClient(supabaseUrl, env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY, options).auth.resetPasswordForEmail(email, { redirectTo })
    : await admin.auth.admin.inviteUserByEmail(email, { redirectTo });

  if (result.error) {
    console.error(`Email could not be sent (HTTP ${result.error.status ?? "unknown"}, code ${result.error.code ?? "unavailable"}). Check Supabase SMTP settings, email rate limits, and allowed redirect URLs.`);
    process.exitCode = 1;
    return;
  }
  console.log(confirmed ? "Password-setup email sent to the configured admin. Check the inbox to choose a password." : "Admin invitation sent. Open the email link to verify the account and choose a password.");
  console.log(`After setup, sign in at ${appOrigin}/login.`);
}

main().catch(() => {
  console.error("Admin setup could not complete. Check APP_URL, NEXT_PUBLIC_SUPABASE_URL, the configured credentials, and network connectivity.");
  process.exitCode = 1;
});
