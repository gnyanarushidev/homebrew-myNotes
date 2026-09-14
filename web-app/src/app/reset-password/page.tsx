import type { Metadata } from "next";
import { AuthForm } from "@/features/auth/auth-form";
import { requireAccount } from "@/server/auth/access";

export const metadata: Metadata = { title: "Reset password" };
export const dynamic = "force-dynamic";
export default async function ResetPasswordPage() {
  const user = await requireAccount();
  return <AuthForm mode="reset" verifiedEmail={user.email} />;
}
