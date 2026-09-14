"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { api, ApiError } from "@/lib/api";
import { readDraft, writeDraft } from "@/lib/drafts";
import { documentSchema, type NotebookDocument, type NotebookRecord } from "@/lib/notebook";

export function useNotebook(userId: string, id: string) {
  const router = useRouter();
  const [document, setDocument] = useState<NotebookDocument | null>(null);
  const [error, setError] = useState("");
  const [status, setStatus] = useState("Loading…");
  const [conflict, setConflict] = useState(false);
  const [copying, setCopying] = useState(false);
  const base = useRef<NotebookRecord | null>(null);
  const current = useRef<NotebookDocument | null>(null);
  const dirty = useRef(false);
  const mounted = useRef(true);
  const running = useRef(false);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const mutation = useRef({ id: "", document: null as NotebookDocument | null });
  const conflictCopy = useRef({ id: "", mutationId: "" });

  const save = useCallback(async function saveSnapshot() {
    if (running.current || !dirty.current || !base.current || !current.current) return;
    running.current = true;
    const snapshot = current.current;
    if (mutation.current.document !== snapshot) mutation.current = { id: crypto.randomUUID(), document: snapshot };
    const mutationId = mutation.current.id;
    if (mounted.current) { setStatus("Saving…"); setError(""); }
    try {
      await writeDraft(userId, id, { record: base.current, document: snapshot, mutationId, savedAt: Date.now(), conflictCopy: conflictCopy.current.id ? conflictCopy.current : undefined });
      const record = await api<NotebookRecord>(`/api/notebooks/${id}`, { method: "PUT", body: JSON.stringify({ id, document: snapshot, revision: base.current.revision, mutationId }) });
      base.current = record;
      window.dispatchEvent(new Event("mynotes-library-change"));
      if (current.current === snapshot) {
        dirty.current = false;
        await writeDraft(userId, id);
        if (mounted.current && !dirty.current) { setStatus("Saved to cloud"); setConflict(false); }
      } else if (current.current) {
        await writeDraft(userId, id, { record, document: current.current, mutationId: crypto.randomUUID(), savedAt: Date.now() });
      }
    } catch (failure) {
      if (mounted.current) {
        setStatus(navigator.onLine ? "Save needs attention" : "Offline · local draft");
        setError((failure as Error).message);
        if (failure instanceof ApiError && [409, 404].includes(failure.status)) setConflict(true);
      }
    } finally {
      running.current = false;
      if (mounted.current && dirty.current && current.current !== snapshot) timer.current = setTimeout(() => void saveSnapshot(), 700);
    }
  }, [id, userId]);

  useEffect(() => {
    mounted.current = true;
    let cancelled = false;
    async function load() {
      const draft = await readDraft(userId, id).catch(() => undefined);
      try {
        const record = await api<NotebookRecord>(`/api/notebooks/${id}`);
        if (cancelled) return;
        const recovered = draft && draft.record.id === id && documentSchema.safeParse(draft.document).success;
        base.current = recovered ? draft.record : record;
        current.current = recovered ? draft.document : record.document;
        dirty.current = Boolean(recovered);
        mutation.current = { id: recovered ? draft.mutationId : "", document: recovered ? draft.document : null };
        if (recovered && draft.conflictCopy) conflictCopy.current = draft.conflictCopy;
        setDocument(current.current);
        setStatus(recovered ? "Recovered local draft" : "Saved to cloud");
        if (recovered) timer.current = setTimeout(() => void save(), 800);
      } catch (failure) {
        if (cancelled) return;
        if (draft && draft.record.id === id && documentSchema.safeParse(draft.document).success && (!(failure instanceof ApiError) || failure.status >= 500 || failure.status === 404)) {
          base.current = draft.record; current.current = draft.document; dirty.current = true;
          mutation.current = { id: draft.mutationId, document: draft.document };
          if (draft.conflictCopy) conflictCopy.current = draft.conflictCopy;
          setDocument(draft.document);
          if (failure instanceof ApiError && failure.status === 404) setConflict(true);
        }
        setStatus("Unable to load cloud version"); setError((failure as Error).message);
      }
    }
    void load();
    const online = () => { void save(); };
    const leaving = (event: BeforeUnloadEvent) => { if (dirty.current) { event.preventDefault(); event.returnValue = ""; } };
    window.addEventListener("online", online); window.addEventListener("beforeunload", leaving);
    return () => {
      cancelled = true; mounted.current = false;
      if (timer.current) clearTimeout(timer.current);
      window.removeEventListener("online", online); window.removeEventListener("beforeunload", leaving);
    };
  }, [id, userId, save]);

  function update(next: NotebookDocument) {
    current.current = next; dirty.current = true; setDocument(next); setStatus("Saving local draft…");
    if (timer.current) clearTimeout(timer.current);
    if (base.current) {
      const mutationId = crypto.randomUUID();
      mutation.current = { id: mutationId, document: next };
      void writeDraft(userId, id, { record: base.current, document: next, mutationId, savedAt: Date.now(), conflictCopy: conflictCopy.current.id ? conflictCopy.current : undefined })
        .then(() => { if (mounted.current && current.current === next) setStatus("Saved locally · pending sync"); })
        .catch(failure => { if (mounted.current) setError((failure as Error).message); });
    }
    timer.current = setTimeout(() => void save(), 900);
  }

  async function keepBoth() {
    if (!current.current || !base.current || running.current) return;
    running.current = true;
    setCopying(true);
    conflictCopy.current.id ||= crypto.randomUUID();
    conflictCopy.current.mutationId ||= crypto.randomUUID();
    try {
      await writeDraft(userId, id, { record: base.current, document: current.current, mutationId: mutation.current.id, savedAt: Date.now(), conflictCopy: conflictCopy.current });
      const copy = { ...current.current, title: `${current.current.title.slice(0, 95)} (conflict copy)` };
      const record = await api<NotebookRecord>("/api/notebooks", { method: "POST", body: JSON.stringify({ ...conflictCopy.current, document: copy }) });
      await writeDraft(userId, record.id, { record, document: { ...current.current, title: copy.title }, mutationId: crypto.randomUUID(), savedAt: Date.now() });
      await writeDraft(userId, id);
      dirty.current = false;
      router.push(`/notebooks/${record.id}`);
    } catch (failure) { setError((failure as Error).message); }
    finally { running.current = false; setCopying(false); }
  }
  return { document, update, status, error, conflict, copying, save, keepBoth };
}
