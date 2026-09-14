import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { AuthFrame } from "@/features/auth/auth-frame";
import { ActionLink } from "@/components/ui/ui";
import { getAccountAccess } from "@/server/auth/access";

export const metadata: Metadata = { title: "Your invitation" };
export const dynamic = "force-dynamic";
export default async function InvitePage() {
  const access = await getAccountAccess();
  if (access.status === "admin" || access.status === "member") redirect("/reset-password");
  return <AuthFrame eyebrow="YOUR INVITATION" title="Open your setup email." description="Use the link in your MyNotes invitation to verify your account and choose a password.">
    <p>If you already activated your account, you can sign in below. If your link has expired, request a new password-reset email.</p>
    <ActionLink href="/login">Sign in</ActionLink>{" "}<ActionLink href="/forgot-password" variant="ghost">Request a new link</ActionLink>
  </AuthFrame>;
}
