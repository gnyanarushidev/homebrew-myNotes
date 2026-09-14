import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { AuthForm } from "@/features/auth/auth-form";
import { getAccountAccess } from "@/server/auth/access";

export const metadata: Metadata = { title: "Sign in" };
export const dynamic = "force-dynamic";
const messages: Record<string, string> = {
  anonymous: "Sign in to open your notebooks.",
  forbidden: "This account has not been invited or its access was revoked.",
  unconfigured: "Authentication is not configured for this deployment. Check its environment settings.",
  unavailable: "Authentication is temporarily unavailable. Please try again.",
  "link-invalid": "This sign-in link is invalid, expired, or belongs to a different account. Request a fresh link.",
  "oauth-failed": "Google sign-in could not be completed. Please try again.",
  "google-unavailable": "Google sign-in is not enabled in Supabase yet. Use your email and password.",
};

export default async function LoginPage({ searchParams }: { searchParams: Promise<{ reason?: string }> }) {
  const access = await getAccountAccess();
  if (access.status === "admin") redirect("/admin");
  if (access.status === "member") redirect("/notebooks");
  const { reason } = await searchParams;
  const error = typeof reason === "string" && Object.hasOwn(messages, reason)
    ? messages[reason]
    : access.status === "unconfigured" ? messages.unconfigured : "";
  return <AuthForm mode="login" initialError={error} />;
}
