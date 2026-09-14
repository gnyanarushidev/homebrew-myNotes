import type { Metadata } from "next";
import { AuthForm } from "@/features/auth/auth-form";
import { requireAdmin } from "@/server/auth/access";

export const metadata: Metadata = { title: "Reset password" };
export const dynamic = "force-dynamic";
export default async function ResetPasswordPage() {
  const user = await requireAdmin();
  return <AuthForm mode="reset" verifiedEmail={user.email} />;
}
