import type { Metadata } from "next";
import { AuthPreview } from "@/features/auth/auth-preview";

export const metadata: Metadata = { title: "Forgot password" };
export default function ForgotPasswordPage() { return <AuthPreview mode="forgot" />; }
