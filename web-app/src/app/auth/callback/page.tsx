import type { Metadata } from "next";
import { AuthPreview } from "@/features/auth/auth-preview";

export const metadata: Metadata = { title: "Authentication callback" };
export default function CallbackPage() { return <AuthPreview mode="callback" />; }
