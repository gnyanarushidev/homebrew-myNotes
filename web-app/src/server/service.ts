import "server-only";
import { createClient, type User } from "@supabase/supabase-js";
import { authFetch, isAllowedAccount, isVerifiedAdmin } from "./auth/client";
import { getAuthSettings } from "./auth/settings";

export function serviceClient() {
  const settings = getAuthSettings();
  const key = process.env.SUPABASE_SECRET_KEY;
  if (!key) throw new Error("Set SUPABASE_SECRET_KEY in the server environment.");
  return createClient(settings.supabaseUrl, key, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    global: { fetch: authFetch },
  });
}

export async function listAccounts() {
  const service = serviceClient();
  const result: User[] = [];
  for (let page = 1; ; page++) {
    const { data, error } = await service.auth.admin.listUsers({ page, perPage: 100 });
    if (error) throw new Error("Unable to load users from Supabase. Check the server secret key.");
    result.push(...data.users);
    if (data.users.length < 100) return result;
  }
}

export async function canRecover(email: string) {
  const settings = getAuthSettings();
  if (email === settings.adminEmail) return true;
  const user = (await listAccounts()).find(user => user.email?.toLowerCase() === email);
  return Boolean(user && user.app_metadata?.mynotes_access === "active");
}

export function accountSummary(user: User) {
  const settings = getAuthSettings();
  const admin = isVerifiedAdmin(user, settings);
  const granted = user.app_metadata?.mynotes_access === "active";
  return {
    id: user.id, email: user.email ?? "", role: admin ? "Admin" : "Member",
    status: admin || isAllowedAccount(user, settings) ? "Active" : user.app_metadata?.mynotes_access === "revoked" ? "Revoked" : granted ? "Invited" : "Not invited",
    createdAt: user.created_at, invitedAt: user.invited_at ?? null,
  };
}
