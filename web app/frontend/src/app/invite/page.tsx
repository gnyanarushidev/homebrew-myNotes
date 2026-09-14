import type { Metadata } from "next";
import { AuthPreview } from "@/features/auth/auth-preview";

export const metadata: Metadata = { title: "Your invitation" };
export default function InvitePage() { return <AuthPreview mode="invite" />; }
