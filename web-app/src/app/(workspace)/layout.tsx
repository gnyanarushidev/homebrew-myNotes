import type { ReactNode } from "react";
import { WorkspaceShell } from "@/features/notebooks/workspace-shell";
import { requireAccount } from "@/server/auth/access";

export const dynamic = "force-dynamic";
export default async function WorkspaceLayout({ children }: { children: ReactNode }) {
  const user = await requireAccount();
  return <WorkspaceShell user={user}>{children}</WorkspaceShell>;
}
