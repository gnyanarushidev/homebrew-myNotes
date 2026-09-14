import type { Metadata } from "next";
import { AuthPreview } from "@/features/auth/auth-preview";

export const metadata: Metadata = { title: "Sign in" };
export default function LoginPage() { return <AuthPreview mode="login" />; }
