"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { loadCloudNotebook, saveCloudNotebook } from "@/lib/cloud-client";
import { api, ApiError } from "@/lib/api";
import { readDraft, writeDraft } from "@/lib/drafts";
import { documentSchema, type NotebookDocument, type NotebookRecord } from "@/lib/notebook";
import { mergeDocuments } from "@/lib/merge";

export function useNotebook(userId: string, id: string) {
  const router = useRouter();
  const [document, setDocument] = useState<NotebookDocument | null>(null);
  const [error, setError] = useState("");
  const [status, setStatus] = useState("Loading…");
  const [conflict, setConflict] = useState(false);
  const [copying, setCopying] = useState(false);
  const [remoteGeneration, setRemoteGeneration] = useState(0);
  const gestures = useRef(0);
  const editing = useCallback((active: boolean) => { gestures.current = Math.max(0, gestures.current + (active ? 1 : -1)); }, []);
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
    const previous = base.current;
    if (mutation.current.document !== snapshot) mutation.current = { id: crypto.randomUUID(), document: snapshot };
    const mutationId = mutation.current.id;
    if (mounted.current) { setStatus("Saving…"); setError(""); }
    try {
      await writeDraft(userId, id, { record: base.current, document: snapshot, mutationId, savedAt: Date.now(), conflictCopy: conflictCopy.current.id ? conflictCopy.current : undefined });
      const record = await saveCloudNotebook(id, snapshot, base.current.revision, mutationId, base.current.storage, userId);
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
      if (failure instanceof ApiError && failure.status === 409) {
        try {
          const remote = await loadCloudNotebook(id, userId);
          const merged = mergeDocuments(previous.document, snapshot, remote.document);
          const latest = merged && current.current ? mergeDocuments(snapshot, current.current, merged) : null;
          if (latest && !gestures.current) {
            const mutationId = crypto.randomUUID();
            base.current = remote; current.current = latest; mutation.current = { id: mutationId, document: latest };
            if (mounted.current) { setDocument(latest); setConflict(false); setError(""); setStatus("Merged cloud changes · saving…"); setRemoteGeneration(value => value + 1); }
            await writeDraft(userId, id, { record: remote, document: latest, mutationId, savedAt: Date.now() });
            return; // finally schedules the merged snapshot; operation ID/base are durable.
          }
        } catch { /* The unchanged local draft remains recoverable. */ }
      }
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
        const record = await loadCloudNotebook(id, userId);
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
    const receive = async () => {
      if (cancelled || gestures.current || dirty.current || running.current || !base.current) return;
      const previous = base.current;
      try {
        const remote = await api<{ revision: number; deleted: boolean }>(`/api/v1/sync/notebooks/${id}`, { headers: { "X-MyNotes-Account": userId } });
        if (cancelled || gestures.current || dirty.current || base.current !== previous) return;
        if (remote.deleted) { setDocument(null); setError("This notebook was deleted on another device."); return; }
        if (remote.revision !== previous.revision) {
          const record = await loadCloudNotebook(id, userId);
          if (cancelled || gestures.current || dirty.current || base.current !== previous) return;
          base.current = record; current.current = record.document; setDocument(record.document); setStatus("Updated from cloud"); setError("");
          setRemoteGeneration(value => value + 1);
          window.dispatchEvent(new Event("mynotes-library-change"));
        }
      } catch { /* Retain the current view during a transient read outage. */ }
    };
    const polling = setInterval(() => void receive(), 15000);
    window.addEventListener("focus", receive);
    const online = () => { void save(); };
    const leaving = (event: BeforeUnloadEvent) => { if (dirty.current) { event.preventDefault(); event.returnValue = ""; } };
    window.addEventListener("online", online); window.addEventListener("beforeunload", leaving);
    return () => {
      cancelled = true; mounted.current = false;
      if (timer.current) clearTimeout(timer.current);
      window.removeEventListener("online", online); window.removeEventListener("beforeunload", leaving);
      clearInterval(polling); window.removeEventListener("focus", receive);
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
      const record = await saveCloudNotebook(conflictCopy.current.id, copy, 0, conflictCopy.current.mutationId, undefined, userId);
      await writeDraft(userId, record.id, { record, document: { ...current.current, title: copy.title }, mutationId: crypto.randomUUID(), savedAt: Date.now() });
      await writeDraft(userId, id);
      dirty.current = false;
      router.push(`/notebooks/${record.id}`);
    } catch (failure) { setError((failure as Error).message); }
    finally { running.current = false; setCopying(false); }
  }
  return { document, update, status, error, conflict, copying, save, keepBoth, editing, remoteGeneration };
}
