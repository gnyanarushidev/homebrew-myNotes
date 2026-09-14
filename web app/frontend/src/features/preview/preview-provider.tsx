"use client";

import { createContext, useContext, useState, type ReactNode } from "react";
import { previewMembers, previewNotebooks, type CoverColor, type PaperTemplate, type PreviewMember, type PreviewNotebook } from "./preview-data";

type PreviewContextValue = {
  notebooks: PreviewNotebook[];
  members: PreviewMember[];
  createNotebook: (title: string, cover: CoverColor, template: PaperTemplate) => string;
  updateNotebook: (id: string, changes: Partial<Pick<PreviewNotebook, "title" | "template" | "pageCount">>) => void;
  inviteMember: (email: string) => boolean;
  revokeInvitation: (id: string) => void;
};

const PreviewContext = createContext<PreviewContextValue | null>(null);

export function PreviewProvider({ children }: { children: ReactNode }) {
  const [notebooks, setNotebooks] = useState(previewNotebooks);
  const [members, setMembers] = useState(previewMembers);

  function createNotebook(title: string, cover: CoverColor, template: PaperTemplate) {
    const id = crypto.randomUUID();
    setNotebooks(current => [{ id, title: title.trim(), cover, template, pageCount: 1, description: "A fresh start for your next idea.", order: Math.max(0, ...current.map(item => item.order)) + 1, sample: false }, ...current]);
    return id;
  }

  function updateNotebook(id: string, changes: Partial<Pick<PreviewNotebook, "title" | "template" | "pageCount">>) {
    setNotebooks(current => current.map(notebook => notebook.id === id ? { ...notebook, ...changes } : notebook));
  }

  function inviteMember(email: string) {
    const normalized = email.trim().toLowerCase();
    if (members.some(member => member.email === normalized && member.status !== "Revoked")) return false;
    setMembers(current => [{ id: crypto.randomUUID(), name: "Invitation pending", email: normalized, role: "Member", status: "Invited" }, ...current]);
    return true;
  }

  function revokeInvitation(id: string) {
    setMembers(current => current.map(member => member.id === id ? { ...member, status: "Revoked" } : member));
  }

  return <PreviewContext.Provider value={{ notebooks, members, createNotebook, updateNotebook, inviteMember, revokeInvitation }}>{children}</PreviewContext.Provider>;
}

export function usePreview() {
  const context = useContext(PreviewContext);
  if (!context) throw new Error("Preview components must be inside PreviewProvider.");
  return context;
}
