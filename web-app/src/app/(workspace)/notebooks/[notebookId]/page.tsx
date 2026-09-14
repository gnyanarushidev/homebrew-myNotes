import type { Metadata } from "next";
import { EditorPreview } from "@/features/notebooks/editor-preview";
import { previewNotebooks } from "@/features/preview/preview-data";

export const metadata: Metadata = { title: "Notebook preview" };
export function generateStaticParams() { return previewNotebooks.map(notebook => ({ notebookId: notebook.id })); }

export default async function NotebookPage({ params }: { params: Promise<{ notebookId: string }> }) {
  const { notebookId } = await params;
  return <EditorPreview notebookId={notebookId} />;
}
