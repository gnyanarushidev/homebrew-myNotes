import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { AuthForm } from "@/features/auth/auth-form";
import { getAdminAccess } from "@/server/auth/access";

export const metadata: Metadata = { title: "Sign in" };
export const dynamic = "force-dynamic";
const messages: Record<string, string> = {
  anonymous: "Sign in to open the admin dashboard.",
  forbidden: "This account does not have administrator access.",
  unconfigured: "Authentication is not configured for this deployment. Check its environment settings.",
  unavailable: "Authentication is temporarily unavailable. Please try again.",
  "link-invalid": "This sign-in link is invalid, expired, or belongs to a different account. Request a fresh link.",
  "oauth-failed": "Google sign-in could not be completed. Please try again.",
  "google-unavailable": "Google sign-in is not enabled in Supabase yet. Use your email and password.",
};

export default async function LoginPage({ searchParams }: { searchParams: Promise<{ reason?: string }> }) {
  const access = await getAdminAccess();
  if (access.status === "admin") redirect("/admin");
  const { reason } = await searchParams;
  const error = typeof reason === "string" && Object.hasOwn(messages, reason)
    ? messages[reason]
    : access.status === "unconfigured" ? messages.unconfigured : "";
  return <AuthForm mode="login" initialError={error} />;
}
