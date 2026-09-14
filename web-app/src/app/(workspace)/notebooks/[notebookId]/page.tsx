import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { z } from "zod";
import { NotebookEditor } from "@/features/notebooks/notebook-editor";
import { requireAccount } from "@/server/auth/access";

export const metadata: Metadata = { title: "Notebook" };

export default async function NotebookPage({ params }: { params: Promise<{ notebookId: string }> }) {
  const { notebookId } = await params;
  if (!z.uuid().safeParse(notebookId).success) notFound();
  const user = await requireAccount();
  return <NotebookEditor key={`${user.id}:${notebookId}`} userId={user.id} notebookId={notebookId} />;
}
