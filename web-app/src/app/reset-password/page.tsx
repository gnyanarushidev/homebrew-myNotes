import type { Metadata } from "next";
import { AuthPreview } from "@/features/auth/auth-preview";

export const metadata: Metadata = { title: "Reset password" };
export default function ResetPasswordPage() { return <AuthPreview mode="reset" />; }
