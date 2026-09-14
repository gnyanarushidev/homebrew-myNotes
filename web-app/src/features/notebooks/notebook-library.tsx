"use client";

import Link from "next/link";
import { useEffect, useRef, useState, type FormEvent } from "react";
import { usePathname, useRouter } from "next/navigation";
import { api } from "@/lib/api";
import { newDocument, templates, paperColors, pageSizes, type Template, type PaperColor, type PageSize, type NotebookRecord, type NotebookSummary } from "@/lib/notebook";
import { Button } from "@/components/ui/ui";
import { Dialog } from "@/components/ui/dialog";
import { Icon } from "@/components/ui/icon";
import ui from "@/components/ui/ui.module.css";
import styles from "./desktop-workspace.module.css";

export function NotebookLibrary({ onNavigate }: { onNavigate: () => void }) {
  const router = useRouter();
  const pathname = usePathname();
  const [notebooks, setNotebooks] = useState<NotebookSummary[]>([]);
  const [query, setQuery] = useState("");
  const [sort, setSort] = useState("recent");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [refresh, setRefresh] = useState(0);
  const [creating, setCreating] = useState(false);
  const [title, setTitle] = useState("");
  const [template, setTemplate] = useState<Template>("blank");
  const [color, setColor] = useState<PaperColor>("white");
  const [size, setSize] = useState<PageSize>("letterPortrait");
  const [busy, setBusy] = useState(false);
  const [deleting, setDeleting] = useState<NotebookSummary | null>(null);
  const pendingCreation = useRef({ id: "", mutationId: "" });
  const pendingImport = useRef({ file: "", id: "", mutationId: "" });
  const file = useRef<HTMLInputElement>(null);
  useEffect(() => {
    const controller = new AbortController();
    const timeout = setTimeout(() => {
      setLoading(true);
      api<NotebookSummary[]>(`/api/notebooks?search=${encodeURIComponent(query)}`, { signal: controller.signal })
        .then(data => { setNotebooks(data); setError(""); })
        .catch(failure => { if (!controller.signal.aborted) setError(failure.message); })
        .finally(() => { if (!controller.signal.aborted) setLoading(false); });
    }, 200);
    return () => { clearTimeout(timeout); controller.abort(); };
  }, [query, refresh, pathname]);
  useEffect(() => {
    const changed = () => setRefresh(value => value + 1);
    window.addEventListener("mynotes-library-change", changed);
    return () => window.removeEventListener("mynotes-library-change", changed);
  }, []);

  async function create(event: FormEvent) {
    event.preventDefault();
    if (busy || !title.trim()) return;
    setBusy(true); setError("");
    pendingCreation.current.id ||= crypto.randomUUID(); pendingCreation.current.mutationId ||= crypto.randomUUID();
    try {
      const record = await api<NotebookRecord>("/api/notebooks", { method: "POST", body: JSON.stringify({ ...pendingCreation.current, document: newDocument(title.trim(), template, color, size) }) });
      setCreating(false); setTitle(""); onNavigate();
      router.push(`/notebooks/${record.id}`);
    } catch (failure) { setError((failure as Error).message); }
    finally { setBusy(false); }
  }
  async function remove() {
    if (!deleting) return;
    setBusy(true); setError("");
    try {
      const record = await api<NotebookRecord>(`/api/notebooks/${deleting.id}`);
      await api(`/api/notebooks/${deleting.id}`, { method: "DELETE", body: JSON.stringify({ revision: record.revision }) });
      setDeleting(null); setRefresh(value => value + 1);
      if (pathname === `/notebooks/${deleting.id}`) router.push("/notebooks");
    } catch (failure) { setError((failure as Error).message); }
    finally { setBusy(false); }
  }
  const visible = [...notebooks].sort((a, b) => sort === "title" ? a.title.localeCompare(b.title) : b.updated_at.localeCompare(a.updated_at));
  return <>
    <div className={styles.libraryActions}><button type="button" disabled={busy} title="New notebook" aria-label="New notebook" onClick={() => { pendingCreation.current = { id: "", mutationId: "" }; setCreating(true); }}><Icon name="plus" />New notebook</button><button type="button" disabled={busy} title="Import Mac notebook or JSON backup" aria-label="Import notebooks" onClick={() => file.current?.click()}><Icon name="export" /></button></div>
    <input ref={file} type="file" accept=".json" hidden onChange={async event => {
      const selected = event.target.files?.[0]; if (!selected) return;
      const input = event.currentTarget;
      setBusy(true); setError("");
      try {
        if (selected.size > 2_900_000) throw new Error("This file exceeds the 2.9 MB import limit. Export a smaller notebook.");
        const raw = await selected.text();
        if (pendingImport.current.file !== raw) pendingImport.current = { file: raw, id: crypto.randomUUID(), mutationId: crypto.randomUUID() };
        const record = await api<NotebookRecord>("/api/notebooks/import", { method: "POST", body: JSON.stringify({ id: pendingImport.current.id, mutationId: pendingImport.current.mutationId, value: JSON.parse(raw), filename: selected.name }) });
        onNavigate(); router.push(`/notebooks/${record.id}`); setRefresh(value => value + 1);
      } catch (failure) { setError((failure as Error).message); } finally { setBusy(false); input.value = ""; }
    }} />
    <label className={styles.search}><Icon name="search" width="15" /><input aria-label="Search notebooks" type="search" placeholder="Search notebooks and notes" value={query} onChange={e => setQuery(e.target.value)} /></label>
    <div className={styles.listHeading}><span>NOTEBOOKS</span><select aria-label="Sort notebooks" value={sort} onChange={e => setSort(e.target.value)}><option value="recent">Recent</option><option value="title">Name</option></select></div>
    {error && <p role="alert" className={ui.errorMessage}>{error} <button type="button" onClick={() => setRefresh(v => v + 1)}>Retry</button></p>}
    {loading && <p className={styles.hint}>Loading library…</p>}
    {!loading && !error && visible.length === 0 && <div className={styles.hint}><h2>{query ? "No matching notebooks" : "Start with a blank page"}</h2><p>{query ? "Try a different search." : "Create a notebook or import your local Mac drawings."}</p></div>}
    <nav className={styles.notebookList} aria-label="Notebooks">{visible.map(notebook => <div key={notebook.id} data-selected={pathname === `/notebooks/${notebook.id}`}>
      <Link href={`/notebooks/${notebook.id}`} prefetch={false} onClick={onNavigate} aria-current={pathname === `/notebooks/${notebook.id}` ? "page" : undefined}><Icon name="book" width="17" /><span>{notebook.title}<small>{notebook.pageCount} {notebook.pageCount === 1 ? "page" : "pages"}</small></span></Link>
      <button type="button" onClick={() => setDeleting(notebook)} aria-label={`Delete ${notebook.title}`}><Icon name="trash" width="14" /></button>
    </div>)}</nav>
    <p className={styles.hint} role="status">{busy ? "Saving…" : `${visible.length} notebooks · Cloud library`}</p>
    <Dialog open={creating} title="New notebook" onClose={() => !busy && setCreating(false)}><form className={styles.dialogForm} onSubmit={create}>
      <label className={ui.field}>Notebook name<input className={ui.input} required maxLength={120} value={title} onChange={e => setTitle(e.target.value)} placeholder="Untitled Notebook" /></label>
      <label className={ui.field}>Paper template<select className={ui.input} value={template} onChange={e => setTemplate(e.target.value as Template)}>{templates.map(value => <option key={value}>{value}</option>)}</select></label>
      <label className={ui.field}>Paper color<select className={ui.input} value={color} onChange={e => setColor(e.target.value as PaperColor)}>{paperColors.map(value => <option key={value}>{value}</option>)}</select></label>
      <label className={ui.field}>Page size<select className={ui.input} value={size} onChange={e => setSize(e.target.value as PageSize)}>{pageSizes.map(value => <option key={value} value={value}>{value === "letterPortrait" ? "US Letter" : "A4"}</option>)}</select></label>
      {error && <p role="alert" className={ui.errorMessage}>{error}</p>}<Button type="submit" disabled={busy}>{busy ? "Creating…" : "Create notebook"}</Button>
    </form></Dialog>
    <Dialog open={Boolean(deleting)} title="Delete notebook?" onClose={() => !busy && setDeleting(null)}><p>Delete “{deleting?.title}” and all its pages? Export a backup first if you need to keep it.</p>{error && <p role="alert">{error}</p>}<Button disabled={busy} onClick={() => void remove()}>Delete notebook</Button></Dialog>
  </>;
}
